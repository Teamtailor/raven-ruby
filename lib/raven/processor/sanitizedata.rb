# frozen_string_literal: true
require 'json'

module Raven
  class Processor::SanitizeData < Processor
    DEFAULT_FIELDS = %w(authorization password passwd secret ssn social(.*)?sec).freeze
    CREDIT_CARD_RE = /^(?:\d[ -]*?){13,16}$/

    attr_accessor :sanitize_fields, :sanitize_credit_cards

    def initialize(client)
      super
      self.sanitize_fields = client.configuration.sanitize_fields
      self.sanitize_credit_cards = client.configuration.sanitize_credit_cards
    end

    def process(value, key = nil)
      case value
      when Hash
        !value.frozen? ? value.merge!(value) { |k, v| process v, k } : value.merge(value) { |k, v| process v, k }
      when Array
        !value.frozen? ? value.map! { |v| process v, key } : value.map { |v| process v, key }
      when Integer
        matches_regexes?(key, value.to_s) ? INT_MASK : value
      when String
        if value =~ fields_re && (json = parse_json_or_nil(value))
          # if this string is actually a json obj, convert and sanitize
          process(json).to_json
        elsif matches_regexes?(key, value)
          STRING_MASK
        elsif key == 'query_string' || key == :query_string
          sanitize_query_string(value)
        else
          value
        end
      else
        value
      end
    end

    private

    def sanitize_query_string(query_string)
      query_hash = CGI.parse(query_string)
      processed_query_hash = process(query_hash)
      URI.encode_www_form(processed_query_hash)
    end

    def matches_regexes?(k, v)
      (sanitize_credit_cards && v =~ CREDIT_CARD_RE) ||
        k =~ fields_re
    end

    def fields_re
      @fields_re ||= /#{(DEFAULT_FIELDS | sanitize_fields).map do |f|
        use_boundary?(f) ? "\\b#{f}\\b" : f
      end.join("|")}/i
    end

    def use_boundary?(string)
      !DEFAULT_FIELDS.include?(string) && !special_characters?(string)
    end

    def special_characters?(string)
      REGEX_SPECIAL_CHARACTERS.select { |r| string.include?(r) }.any?
    end

    def parse_json_or_nil(string)
      return unless string.start_with?("[", "{")
      JSON.parse(string)
    rescue JSON::ParserError, NoMethodError
      nil
    end
  end
end
