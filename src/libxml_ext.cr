require "xml"

lib LibXML
  fun xmlNewText(content : UInt8*) : Node*
  fun xmlAddChild(parent : Node*, child : Node*) : Node*
  fun xmlReplaceNode(node : Node*, other : Node*) : Node*
  fun xmlAddNextSibling(node : Node*, other : Node*) : Node*
  fun xmlAddPrevSibling(node : Node*, other : Node*) : Node*
  fun xmlCopyNode(node : Node*, extended : Int) : Node*
  fun xmlCopyDoc(node : Doc*, recursive : Int) : Doc*
end

struct XML::Node
  # Creates a new text node.
  def initialize(text : String)
    @node = LibXML.xmlNewText(text)
  end

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

  # Performs a deep copy on this node.
  def clone
    self.class.new(LibXML.xmlCopyNode(self, 1)).tap do |clone|
      self.class.new(LibXML.xmlCopyDoc(@node.value.doc, 0)).tap do |document|
        document.add_child(clone)
      end
    end
  end
end
