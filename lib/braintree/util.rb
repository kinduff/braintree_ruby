module Braintree
  module Util # :nodoc:
    def self.extract_attribute_as_array(hash, attribute)
      value = hash.delete(attribute)
      value.is_a?(Array) ? value : [value]
    end

    def self.hash_to_query_string(hash, namespace = nil)
      hash.collect do |key, value|
        full_key = namespace ? "#{namespace}[#{key}]" : key
        if value.is_a?(Hash)
          hash_to_query_string(value, full_key)
        else
          url_encode(full_key) + "=" + url_encode(value)
        end
      end.sort * '&'
    end
    
    def self.parse_query_string(qs)
      qs.split('&').inject({}) do |result, couplet|
        pair = couplet.split('=')
        result[CGI.unescape(pair[0]).to_sym] = CGI.unescape(pair[1])
        result
      end
    end
    
    def self.url_encode(text)
      CGI.escape text.to_s
    end

    def self.symbolize_keys(hash)
      hash.each do |key, value|
        hash.delete(key)
        hash[key.to_sym] = value
        if value.is_a?(Hash)
          symbolize_keys(value)
        elsif value.is_a?(Array) && value.all? { |v| v.is_a?(Hash) }
          value.each { |v| symbolize_keys(v) }
        end
      end 
      hash
    end
    
    def self.raise_exception_for_status_code(status_code)
      case status_code.to_i
      when 401
        raise AuthenticationError
      when 403
        raise AuthorizationError
      when 404
        raise NotFoundError
      when 500
        raise ServerError
      when 503
        raise DownForMaintenanceError
      else
        raise UnexpectedError, "Unexpected HTTP_RESPONSE #{status_code.to_i}"
      end
    end
    
    def self.verify_keys(valid_keys, hash)
      invalid_keys = _flatten_hash_keys(hash) - _flatten_valid_keys(valid_keys)
      if invalid_keys.any?
        sorted = invalid_keys.sort_by { |k| k.to_s }.join(", ")
        raise ArgumentError, "invalid keys: #{sorted}"
      end
    end
    
    def self._flatten_valid_keys(valid_keys, namespace = nil)
      valid_keys.inject([]) do |result, key|
        if key.is_a?(Hash)
          full_key = key.keys[0]
          full_key = (namespace ? "#{namespace}[#{full_key}]" : full_key)
          result += _flatten_valid_keys(key.values[0], full_key)
        else
          result << (namespace ? "#{namespace}[#{key}]" : key.to_s)
        end
        result
      end.sort
    end
    
    def self._flatten_hash_keys(hash, namespace = nil)
      hash.inject([]) do |result, (key, value)|
        full_key = (namespace ? "#{namespace}[#{key}]" : key.to_s)
        if value.is_a?(Hash)
          result += _flatten_hash_keys(value, full_key)
        else
          result << full_key
        end
        result
      end.sort
    end
  end
end
