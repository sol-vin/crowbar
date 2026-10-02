require "./crowbar/version"
require "./crowbar/prng"
require "./crowbar/buffer"
require "./crowbar/metadata"
require "./crowbar/context"
require "./crowbar/mutators/pool"
require "./crowbar/patterns/base"
require "./crowbar/selectors/base"
require "./crowbar/rules/base"
require "./crowbar/rules/json"
require "./crowbar/rules/yaml"
require "./crowbar/rules/http"
require "./crowbar/rules/dns"
require "./crowbar/evolution/manager"
require "./crowbar/engine"
require "./crowbar/dsl/builder"

{% unless flag?(:release) %}
  require "./docs"
{% end %}

# Top-level namespace for the Crowbar library
module Crowbar
  # Returns the current library version
  def self.version : String
    VERSION
  end
end
