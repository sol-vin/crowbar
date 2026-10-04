require "./crowbar/version"
require "./crowbar/prng"
require "./crowbar/buffer"
require "./crowbar/metadata"
require "./crowbar/context"
require "./crowbar/mutators/pool"
require "./crowbar/patterns/base"
require "./crowbar/selectors/base"
require "./crowbar/rules/base"
require "./crowbar/rules/registry"
require "./crowbar/evolution/manager"
require "./crowbar/evolution/uniqueness_filter"
require "./crowbar/template"
require "./crowbar/engine"
require "./crowbar/dsl/builder"
require "./crowbar/session"

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
