require "xml"

lib LibXML
  fun xmlAddChild(parent : Node*, child : Node*) : Node*
  fun xmlReplaceNode(node : Node*, other : Node*) : Node*
  fun xmlAddNextSibling(node : Node*, other : Node*) : Node*
  fun xmlAddPrevSibling(node : Node*, other : Node*) : Node*
end

struct XML::Node
  # Adds a child node to this node, after existing children, merging
  # adjacent text nodes. Returns the child node.
  def add_child(child : Node)
    LibXML.xmlUnlinkNode(child)
    LibXML.xmlAddChild(self, child)
    child
  end

  # Replaces this node with the other node. Returns the other node.
  def replace_with(other : Node)
    LibXML.xmlUnlinkNode(other)
    LibXML.xmlReplaceNode(self, other)
    other
  end

  # Adds a sibling before or after this node. By default, it adds the
  # sibling after this node. Returns the sibling node.
  def add_sibling(other : Node, position = :after)
    case position
    when :after
      LibXML.xmlUnlinkNode(other)
      LibXML.xmlAddNextSibling(self, other)
    when :before
      LibXML.xmlUnlinkNode(other)
      LibXML.xmlAddPrevSibling(self, other)
    else
      raise NotImplementedError.new("position: #{position}")
    end
    other
  end
end
