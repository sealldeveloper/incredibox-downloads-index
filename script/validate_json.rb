#!/usr/bin/env ruby

# Validates JSON files in the _data directory

require 'json'
require 'set'

module ExitCodes
    SUCCESS = 0
    PARSE_FAILED = 1               # JSON parse errors
    UNSORTED = 2                   # data keys are not in alphanumeric order
    MISSING_URL = 3                # Entry missing the required 'url' field
    MISSING_availability = 4         # Entry missing the required 'availability' field
    MISSING_DOMAINS = 5            # Entry missing the required 'domains' field
    MISSING_LANGUAGE_KEYS = 6      # Translation missing required keys
    MISSING_NAME = 7               # Entry missing the required 'name' field
    UNEXPECTED_availability = 8      # Unexpected value for 'availability' field
    UNEXPECTED_LANGUAGE = 9        # Unexpected language code for 'url_code' field
    UNEXPECTED_LANGUAGE_KEY = 10   # Unexpected language key for translation
    UNSUPPORTED_FIELD = 11         # Unsupported field for site entry
    UNEXPECTED_NOTES = 12          # Unexpected notes key for translation
end

SupportedDifficulties = ["downloadable", "partially", "unfinished", "lost", "unavailable", "demo"]
SupportedEntryKeys = ["availability", "names", "email", "email_body", "email_subject", "meta", "name", "notes", "url", "windows", "mac", "android", "webapp", "song", "creator", "original", "original_url"]
SupportedLanguageKeys = [
    "about",
    "availability",
    "availability_demo",
    "availability_downloadable",
    "availability_lost",
    "availability_partially",
    "availability_unavailable",
    "availability_unfinished",
    "contribute",
    "defaultnote_downloadable",
    "defaultnote_email",
    "footercredits",
    "guide",
    "guidedemo",
    "guidedownloadable",
    "guideexplanations",
    "guidelost",
    "guidepartially",
    "guideunavailable",
    "guideunfinished",
    "hideinfo",
    "jgmd",
    "name",
    "noinfo",
    "noresults",
    "noresultshelp",
    "popular",
    "pullrequest",
    "reset",
    "search",
    "sendmail",
    "showinfo",
    "tagline",
    "title",
    "whatisthis",
    "whatisthis1",
    "whatisthis4"
]

def get_supported_languages()
    return translation_files = Dir.children('_data/trans/').map { |f| f.delete_suffix('.json') }
end

SupportedLanguages = get_supported_languages()

def get_transformed_name(site_object)
    return site_object['name'].downcase.sub(/^the\s+/, '')
end

def validate_accepted_keys(key)
    key.keys.each do |entry_key|
        if entry_key.start_with?('url_') || entry_key.start_with?('notes_')
            # These have their own validation methods
            next
        end

        unless SupportedEntryKeys.include?(entry_key)
            STDERR.puts "Entry '#{key['name']}' has unsupported field: "\
                        "'#{entry_key}'.\n"\
                        "Use one of the supported fields:\n"\
                        "\t#{SupportedEntryKeys}"
            exit ExitCodes::UNSUPPORTED_FIELD
        end
    end
end

def error_on_missing_field(key, field, exit_code)
    unless key.key?(field)
        STDERR.puts "Entry '#{key['name']}' has no '#{field}' field"
        exit exit_code
    end
end

def validate_availability(key)
    availability = key['availability']
    unless SupportedDifficulties.include?(availability)
        STDERR.puts "Entry '#{key['name']}' has unexpected 'availability' field:"\
                    "'#{availability}'.\n"\
                    "Use one of the supported availability values:\n"\
                    "\t#{SupportedDifficulties}"
        exit ExitCodes::UNEXPECTED_availability
    end
end

def validate_localized_urls(key)
    key.keys.each do |entry_key|
        if entry_key.start_with?('url_') && !SupportedLanguages.any? { |lang| entry_key.eql?("url_#{lang}") }
            STDERR.puts "Entry '#{key['name']}' has unrecognized language code: "\
                        "'#{entry_key}'.\n"\
                        "Use one of the supported languages:\n"\
                        "\t#{SupportedLanguages}"
            exit ExitCodes::UNEXPECTED_LANGUAGE
        end
    end
end

def validate_localized_notes(key)
    key.keys.each do |entry_key|
        if entry_key.start_with?('notes_') && !SupportedLanguages.any? { |lang| entry_key.eql?("notes_#{lang}") }
            STDERR.puts "Entry '#{key['name']}' has unrecognized notes code: "\
                        "'#{entry_key}'.\n"\
                        "Use one of the supported languages:\n"\
                        "\t#{SupportedLanguages}"
            exit ExitCodes::UNEXPECTED_NOTES
        end
    end
end

def validate_website_entry(key, i)
    unless key.key?('name')
        STDERR.puts "Entry #{i} has no 'name' field"
        exit ExitCodes::MISSING_NAME
    end
    validate_accepted_keys(key)
    error_on_missing_field(key, 'availability', ExitCodes::MISSING_availability)
    error_on_missing_field(key, 'names', ExitCodes::MISSING_DOMAINS)
    validate_availability(key)
    validate_localized_urls(key)
    validate_localized_notes(key)
end

def add_valid_language_key(keys_in_language_json, key, file)
    if SupportedLanguageKeys.include?(key)
        keys_in_language_json << key
    else
        STDERR.puts "Invalid key '#{key}' for file '#{file}'"
        exit ExitCodes::UNEXPECTED_LANGUAGE_KEY
    end
end

def validate_site_translation(is_sites_json, keys_in_language_json, file)
    unless is_sites_json
        unless keys_in_language_json == SupportedLanguageKeys
            STDERR.puts "Missing language keys in '#{file}': "\
                        "'#{SupportedLanguageKeys - keys_in_language_json}'"
            exit ExitCodes::MISSING_LANGUAGE_KEYS
        end
    end
end

json_files = Dir.glob('_data/**/*').select { |f| File.file?(f) }
json_files.each do |file|
    begin
        json = JSON.parse(File.read(file))
        is_sites_json = File.basename(file) =~ /sites.json/
        keys_in_language_json = []
        # check for alphabetical ordering
        json.each_with_index do |(key, _), i|
            # sites.json is an array of objects; this would expand to:
            #   key = { ... }
            #   i = 0
            # hence, the key variable holds the actual value
            if is_sites_json
                validate_website_entry(key, i)
                name = get_transformed_name(key)
                prev_name = get_transformed_name(json[i - 1])
            else
                name = key
                prev_name = json.keys[i - 1]
                add_valid_language_key(keys_in_language_json, key, file)
            end
            if i > 0 && prev_name > name
                STDERR.puts 'Sorting error in ' + file
                STDERR.puts 'Keys must be in alphanumeric order. ' + \
                            prev_name + ' needs to come after ' + name
                exit ExitCodes::UNSORTED
            end
        end
        validate_site_translation(is_sites_json, keys_in_language_json, file)
    rescue JSON::ParserError => error
        STDERR.puts 'JSON parsing error encountered!'
        STDERR.puts error.backtrace.join("\n")
        exit ExitCodes::PARSE_FAILED
    end
end

exit ExitCodes::SUCCESS
