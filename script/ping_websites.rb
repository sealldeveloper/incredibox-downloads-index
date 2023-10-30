#!/usr/bin/env ruby

# Prints sites.json entries containing links which may be out of operation or
# unreachable

require "net/http"
require "json"

# Taken from https://rossta.net/blog/a-ruby-antihero-thread-pool.html
class ThreadPool
    def initialize(size)
        @size = size
        @jobs = Queue.new
        @pool = Array.new(@size) do |i|
            Thread.new do
                Thread.current[:id] = i
                catch(:exit) do
                    loop do
                        job, args = @jobs.pop
                        job.call(*args)
                    end
                end
            end
        end
    end

    # add a job to queue
    def schedule(*args, &block)
        @jobs << [block, args]
    end

    # run threads and perform jobs from queue
    def run!
        @size.times do
            schedule { throw :exit }
        end
        @pool.map(&:join)
    end
end

def url_exist(name, url_string)
    if (defined?(url_string)).nil?
        url = URI.parse(url_string.strip)
        res = Net::HTTP.get_response(url)
        if res.kind_of?(Net::HTTPRedirection)
            # Do nothing
        elsif res.code == "404"
            STDERR.puts "Entry #{name} returned HTTP 404"
        end
    end
rescue  Errno::EADDRNOTAVAIL,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::ENOENT,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        EOFError,
        SocketError,
        Zlib::DataError => e
    # All categories where a site is most definitely non-operational
    puts "HTTP request failed to #{name}: #{e.inspect}"
    false
rescue OpenSSL::SSL::SSLError
    # Websites with certificate errors are responding to requests
    true
end

json = JSON.parse(File.read('_data/sites.json'))
pool = ThreadPool.new(20)
# check if a website is alive
json.each_with_index do |(key, _), i|
    name = key['name']
    url = key['url']
    windows = key['windows']
    android = key['android']
    mac = key['mac']
    webapp = key['webapp']
    originalurl = key['original_url']
    pool.schedule(name, url, windows, android, mac, webapp, originalurl) do |name , url, windows, android, mac, webapp, originalurl|
        url_exist(name, url)
        url_exist(name, windows)
        url_exist(name, android)
        url_exist(name, mac)
        url_exist(name, webapp)
        url_exist(name, originalurl)
    end
end
pool.run!
