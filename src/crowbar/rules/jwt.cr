require "json"
require "base64"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for JSON Web Tokens (RFC 7519).
  # Decodes header, payload, and signature segments, performs security-focused
  # mutations (algorithm confusion, claim boundary testing, kid injection,
  # privilege escalation, signature tampering), and re-encodes as valid Base64URL.
  class JWTRule < Rule
    def name : String
      "jwt"
    end

    def description : String
      "Structure-preserving RFC 7519 JSON Web Token security mutation (alg confusion, claims, signatures)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      parts = str.split('.')
      return false unless parts.size == 3

      # Header and payload must be non-empty Base64URL
      return false if parts[0].empty? || parts[1].empty?

      # Verify header decodes to valid JSON object
      hdr_json = Base64.decode_string(parts[0])
      hdr = JSON.parse(hdr_json)
      return false unless hdr.as_h?

      # Verify payload decodes to valid JSON object
      payload_json = Base64.decode_string(parts[1])
      pld = JSON.parse(payload_json)
      return false unless pld.as_h?

      true
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      str = buffer.to_s.strip
      parts = str.split('.')
      return false unless parts.size == 3

      hdr_str = Base64.decode_string(parts[0])
      pld_str = Base64.decode_string(parts[1])
      sig_str = parts[2]

      hdr = JSON.parse(hdr_str).as_h
      pld = JSON.parse(pld_str).as_h

      action = context.prng.rand(3)
      case action
      when 0
        # Mutate Header
        mutate_header(hdr, context)
      when 1
        # Mutate Payload
        mutate_payload(pld, context)
      else
        # Tamper Signature
        sig_str = tamper_signature(sig_str, context)
      end

      # Encode back to Base64URL without padding
      new_hdr_b64 = Base64.urlsafe_encode(hdr.to_json, padding: false)
      new_pld_b64 = Base64.urlsafe_encode(pld.to_json, padding: false)
      jwt_out = "#{new_hdr_b64}.#{new_pld_b64}.#{sig_str}"

      # Guarantee mutation if random pick produced identical value
      if jwt_out == str
        pld["fuzz"] = JSON::Any.new(context.prng.rand(100_000_i64))
        new_pld_b64 = Base64.urlsafe_encode(pld.to_json, padding: false)
        jwt_out = "#{new_hdr_b64}.#{new_pld_b64}.#{sig_str}"
      end

      buffer.replace_range(0, buffer.size, jwt_out.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_header(hdr : Hash(String, JSON::Any), context : Context) : Nil
      choice = context.prng.rand(4)
      case choice
      when 0
        # Alg confusion: "none", "None", "NONE", "HS256", "RS256"
        algs = ["none", "None", "NONE", "HS256", "RS256", "ES256", "null", ""]
        hdr["alg"] = JSON::Any.new(context.prng.choice(algs))
      when 1
        # Key ID (kid) injection: directory traversal, SQLi, null byte, command injection
        kids = [
          "../../../../dev/null",
          "../../../../etc/passwd",
          "' UNION SELECT 'secret'--",
          "keys/public.key",
          "secret\x00key",
          "| cat /etc/passwd",
        ]
        hdr["kid"] = JSON::Any.new(context.prng.choice(kids))
      when 2
        # Header parameter injection (jwk, x5u, crit)
        case context.prng.rand(3)
        when 0
          # Rogue jwk public key injection
          hdr["jwk"] = JSON.parse(%({"kty":"RSA","n":"AQAB","e":"AQAB"}))
        when 1
          hdr["x5u"] = JSON::Any.new("http://127.0.0.1:8080/cert.pem")
        else
          hdr["typ"] = JSON::Any.new("JWT_CONFUSED")
        end
      else
        # Generic leaf mutation on header
        if !hdr.empty?
          key = context.prng.choice(hdr.keys)
          hdr[key] = JSON::Any.new("fuzzed_#{context.prng.rand(1000)}")
        end
      end
    end

    private def mutate_payload(pld : Hash(String, JSON::Any), context : Context) : Nil
      choice = context.prng.rand(4)
      case choice
      when 0
        # Timestamp boundary testing (exp, iat, nbf)
        time_keys = ["exp", "iat", "nbf"].select { |k| pld.has_key?(k) }
        time_keys << "exp" if time_keys.empty?
        target_key = context.prng.choice(time_keys)
        boundaries = [0_i64, -1_i64, 2147483647_i64, 9007199254740991_i64, Int64::MAX, Int64::MIN]
        pld[target_key] = JSON::Any.new(context.prng.choice(boundaries))
      when 1
        # Privilege escalation / role tampering
        role_keys = ["role", "roles", "admin", "is_admin", "scope", "permissions"].select { |k| pld.has_key?(k) }
        if role_keys.empty?
          curr_admin = pld["admin"]?.try(&.as_bool?)
          pld["admin"] = JSON::Any.new(curr_admin.nil? ? true : !curr_admin)
          pld["role"] = JSON::Any.new("admin")
        else
          rk = context.prng.choice(role_keys)
          case rk
          when "admin", "is_admin"
            curr = pld[rk]?.try(&.as_bool?)
            pld[rk] = JSON::Any.new(curr.nil? ? true : !curr)
          else
            curr_str = pld[rk]?.try(&.as_s?) || ""
            candidates = ["admin", "root", "superuser", "system", "guest", ""].reject { |c| c == curr_str }
            pld[rk] = JSON::Any.new(context.prng.choice(candidates))
          end
        end
      when 2
        # User identity boundary
        sub_keys = ["sub", "user", "username", "email"].select { |k| pld.has_key?(k) }
        if !sub_keys.empty?
          sk = context.prng.choice(sub_keys)
          pld[sk] = JSON::Any.new(context.prng.choice(["admin", "root", "", "guest", "' OR '1'='1"]))
        else
          pld["sub"] = JSON::Any.new("admin")
        end
      else
        # Mutate existing random leaf
        if !pld.empty?
          key = context.prng.choice(pld.keys)
          pld[key] = JSON::Any.new("tampered_#{context.prng.rand(9999)}")
        end
      end
    end

    private def tamper_signature(sig : String, context : Context) : String
      case context.prng.rand(4)
      when 0
        # Empty signature (alg: none exploit)
        ""
      when 1
        # Bit flip / character mutation in signature
        if sig.size > 2
          chars = sig.chars
          idx = context.prng.rand(chars.size)
          chars[idx] = chars[idx] == 'A' ? 'B' : 'A'
          chars.join
        else
          "AAAA"
        end
      when 2
        # Truncated signature
        sig.size > 4 ? sig[0, sig.size // 2] : ""
      else
        # Zero-filled base64
        "A" * [sig.size, 16].max
      end
    end
  end
end
