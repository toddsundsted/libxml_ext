require "xml"

{% if compare_versions(Crystal::VERSION, "1.17.0") < 0 %}
  {% raise "libxml_ext requires Crystal >= 1.17.0" %}
{% elsif compare_versions(Crystal::VERSION, "1.18.0") < 0 %}
  # Patch XML::NodeSet to fix pointer access issue in core library:
  # https://github.com/crystal-lang/crystal/pull/16055
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
{% if compare_versions(Crystal::VERSION, "1.19.0") < 0 %}
  # Patch XML parse methods to fix parser context memory leak:
  # https://github.com/crystal-lang/crystal/pull/16406
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
  fun xmlCopyNode(node : Node*, extended : Int) : Node*
  fun xmlCopyDoc(node : Doc*, recursive : Int) : Doc*
end

class XML::Node
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
