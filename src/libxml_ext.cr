require "xml"

{% if compare_versions(Crystal::VERSION, "1.17.0") < 0 %}
  {% raise "libxml_ext requires Crystal >= 1.17.0" %}
{% end %}

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

# Patch XML parse methods to fix parser context memory leak:
# https://github.com/crystal-lang/crystal/pull/16414
{% if compare_versions(Crystal::VERSION, "1.19.0") < 0 %}
  lib LibXML
    fun xmlFreeParserCtxt(ctxt : ParserCtxt)
    fun htmlFreeParserCtxt(ctxt : HTMLParserCtxt)
  end

  module XML
    def self.parse(string : String, options : ParserOptions = ParserOptions.default) : Document
      raise XML::Error.new("Document is empty", 0) if string.empty?
      ctxt = LibXML.xmlNewParserCtxt
      begin
        from_ptr(ctxt) do
          LibXML.xmlCtxtReadMemory(ctxt, string, string.bytesize, nil, nil, options)
        end
      ensure
        LibXML.xmlFreeParserCtxt(ctxt)
      end
    end

    def self.parse(io : IO, options : ParserOptions = ParserOptions.default) : Document
      ctxt = LibXML.xmlNewParserCtxt
      begin
        from_ptr(ctxt) do
          LibXML.xmlCtxtReadIO(ctxt, ->read_callback, ->close_callback, Box(IO).box(io), nil, nil, options)
        end
      ensure
        LibXML.xmlFreeParserCtxt(ctxt)
      end
    end

    def self.parse_html(string : String, options : HTMLParserOptions = HTMLParserOptions.default) : Document
      raise XML::Error.new("Document is empty", 0) if string.empty?
      ctxt = LibXML.htmlNewParserCtxt
      begin
        from_ptr(ctxt) do
          LibXML.htmlCtxtReadMemory(ctxt, string, string.bytesize, nil, "utf-8", options)
        end
      ensure
        LibXML.htmlFreeParserCtxt(ctxt)
      end
    end

    def self.parse_html(io : IO, options : HTMLParserOptions = HTMLParserOptions.default) : Document
      ctxt = LibXML.htmlNewParserCtxt
      begin
        from_ptr(ctxt) do
          LibXML.htmlCtxtReadIO(ctxt, ->read_callback, ->close_callback, Box(IO).box(io), nil, "utf-8", options)
        end
      ensure
        LibXML.htmlFreeParserCtxt(ctxt)
      end
    end
  end
{% end %}

lib LibXML
  fun xmlNewText(content : UInt8*) : Node*
  fun xmlAddChild(parent : Node*, child : Node*) : Node*
  fun xmlReplaceNode(node : Node*, other : Node*) : Node*
  fun xmlAddNextSibling(node : Node*, other : Node*) : Node*
  fun xmlAddPrevSibling(node : Node*, other : Node*) : Node*
  fun xmlNewDoc(version : UInt8*) : Doc*
end

class XML::Node
  # Returns a new text node.
  #
  def self.new(text : String)
    raise ArgumentError.new("cannot include null byte") if text.includes?('\0')
    doc = LibXML.xmlNewDoc(nil)
    document = Document.new(doc)
    text = LibXML.xmlNewText(text)
    node = new(text, document)
    LibXML.xmlAddChild(document, node)
    node
  end

  # Recursively moves nodes.
  #
  # Enforces the following rules (from the library documentation):
  #
  #   ...when a libxml node is moved to another document, then the
  #   @document reference of its XML::Node and any instantiated
  #   descendant must be updated to point to the new document Node.
  #
  #   ...the libxml node, along with any descendant shall be removed
  #   from the unlinked nodes list when relinked into a tree, be it
  #   the same document or another.
  #
  #   ...when a XML::Node is moved to another document, the XML::Node
  #   and any instantiated descendant XML::Node shall be cleaned from
  #   the original document's cache, and must be added to the new
  #   document's cache.
  #
  private def move_nodes(node_p : Pointer(LibXML::Node), from : Document, to : Document)
    if (ref = from.cache.delete(node_p))
      to.cache[node_p] = ref
      if (node = ref.value)
        node.document = to
      end
    end
    from.unlinked_nodes.delete(node_p)
    node_p = node_p.value.children
    while node_p
      move_nodes(node_p, from, to)
      node_p = node_p.value.next
    end
  end

  protected setter document

  # Adds a child node to this node after any existing children.
  #
  # Does not support adding text nodes because `xmlAddChild` merges
  # adjacent text nodes automatically, and this method does not
  # accommodate that yet. The restriction on "non-element" nodes is
  # overly broad.
  #
  # Returns the child node.
  #
  def add_child(child : Node)
    raise ArgumentError.new("cannot add non-element node") unless child.element?
    child.unlink
    LibXML.xmlAddChild(self, child)
    move_nodes(child.@node, child.document, self.document)
    child
  end

  # Replaces this node with the other node.
  #
  # Returns the other node.
  #
  def replace_with(other : Node)
    other.unlink
    LibXML.xmlReplaceNode(self, other)
    self.document.unlinked_nodes.add(self.@node)
    move_nodes(other.@node, other.document, self.document)
    other
  end

  enum Position
    After
    Before
  end

  # Adds a sibling before or after this node.
  #
  # By default, it adds the sibling after this node.
  #
  # Returns the sibling node.
  #
  def add_sibling(sibling : Node, position : Position = Position::After)
    sibling.unlink
    case position
    in Position::After
      LibXML.xmlAddNextSibling(self, sibling)
    in Position::Before
      LibXML.xmlAddPrevSibling(self, sibling)
    end
    move_nodes(sibling.@node, sibling.document, self.document)
    sibling
  end
end
