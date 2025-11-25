# Patch XML Document to fix comparison in finalizer.
# https://github.com/crystal-lang/crystal/pull/16418
{% if compare_versions(Crystal::VERSION, "1.19.0") < 0 %}
  class XML::Document < XML::Node
    def finalize
      @unlinked_nodes.each do |node|
        if node.value.doc.as(LibXML::Node*) == @node
          LibXML.xmlFreeNode(node)
        end
      end
      LibXML.xmlFreeDoc(@node.as(LibXML::Doc*))
    end
  end
{% end %}
