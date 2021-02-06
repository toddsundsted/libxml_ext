require "xml"

lib LibXML
  fun xmlAddChild(parent : Node*, child : Node*) : Node*
end

struct XML::Node
  # Adds a child node to this node, after existing children, merging
  # adjacent text nodes. Returns the child node.
  def add_child(child : Node)
    LibXML.xmlUnlinkNode(child)
    LibXML.xmlAddChild(self, child)
    child
  end
end
