module Crowbar
  {% if @top_level.has_constant?(:Carbon) %}
    Carbon.version!
  {% else %}
    VERSION = "0.1.37"

    def self.version : String
      VERSION
    end
  {% end %}
end
