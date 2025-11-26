# Patch XML::NodeSet to fix pointer access issue in core library:
# https://github.com/crystal-lang/crystal/pull/16055
{% if compare_versions(Crystal::VERSION, "1.18.0") < 0 %}
  struct XML::NodeSet
    def self.new(doc : Node, set : LibXML::NodeSet*)
      return NodeSet.new unless set && set.value.node_nr > 0

      nodes = Slice(Node).new(set.value.node_nr) do |i|
        Node.new(set.value.node_tab[i], doc)
      end
      NodeSet.new(nodes)
    end
  end
{% end %}
