require "xml"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for XML / HTML documents.
  # Parses document tree using Crystal's native XML engine, maintaining valid well-formed
  # markup while mutating text nodes, element attributes, tag hierarchies, and namespaces.
  class XMLRule < Rule
    def name : String
      "xml"
    end

    def description : String
      "Structure-preserving XML/HTML document mutation (valid syntax with transformed nodes/attrs)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      return false unless str.starts_with?('<') && str.ends_with?('>')
      XML.parse(str)
      true
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s
      doc = XML.parse(raw_str)
      root = doc.root
      return false unless root

      elements = collect_elements(root)
      return false if elements.empty?

      target = context.prng.choice(elements)

      case context.prng.rand(4)
      when 0
        # Mutate inner text content
        mutate_text(target, context)
      when 1
        # Mutate attributes
        mutate_attributes(target, context)
      when 2
        # Mutate tag name or remove node
        if target != root && context.prng.rand_bool
          target.unlink
        else
          target.name = target.name + "_ext"
        end
      else
        # Wrap content in CDATA or repeated inner text
        wrap_element(target, context)
      end

      new_xml = doc.to_xml
      buffer.replace_range(0, buffer.size, new_xml.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def collect_elements(node : XML::Node) : Array(XML::Node)
      result = [] of XML::Node
      if node.element?
        result << node
        node.children.each do |child|
          result.concat(collect_elements(child))
        end
      end
      result
    end

    private def mutate_text(node : XML::Node, context : Context)
      old_content = node.content
      new_content = case context.prng.rand(4)
                    when 0 then ""
                    when 1 then context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
                    when 2 then old_content * context.prng.rand(2..5)
                    else        "\u202E" + old_content
                    end
      node.content = new_content
    end

    private def mutate_attributes(node : XML::Node, context : Context)
      attrs = node.attributes
      if attrs.empty? || context.prng.rand_bool
        # Add a new attribute
        key = "fuzz_" + context.prng.rand(100).to_s
        val = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
        node[key] = val
      else
        # Mutate existing attribute value
        attr_key = context.prng.choice(attrs.map(&.name))
        node[attr_key] = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end

    private def wrap_element(node : XML::Node, context : Context)
      old_content = node.content
      node.content = "<![CDATA[" + old_content + "]]>"
    end
  end
end
