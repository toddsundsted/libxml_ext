require "xml"

{% if compare_versions(Crystal::VERSION, "1.19.1") < 0 %}
  {% raise "libxml_ext requires Crystal >= 1.19.1" %}
{% end %}

lib LibXML
  fun xmlNewText(content : UInt8*) : Node*
  fun xmlAddChild(parent : Node*, child : Node*) : Node*
  fun xmlReplaceNode(node : Node*, other : Node*) : Node*
  fun xmlAddNextSibling(node : Node*, other : Node*) : Node*
  fun xmlAddPrevSibling(node : Node*, other : Node*) : Node*
  fun xmlNewDoc(version : UInt8*) : Doc*
  fun xmlMemFree(mem : Void*)
  fun xmlDOMWrapAdoptNode(
    ctxt : Void*,
    sourceDoc : Doc*,
    node : Node*,
    destDoc : Doc*,
    destParent : Node*,
    options : Int32
  ) : Int32
end

class XML::Attributes
  # PATCH
  # Patch `XML::Attributes#delete` to fix memory leak when deleting attributes with content.
  # See: https://github.com/crystal-lang/crystal/issues/16685
  #
  def delete(name : String) : String?
    prop = find_prop(name)
    return unless prop

    value = ""
    if content = LibXML.xmlNodeGetContent(prop)
      begin
        value = String.new(content)
      ensure
        LibXML.xmlMemFree(content.as(Void*))
      end
    end

    if node = @node.document.cached?(prop)
      # can't call xmlUnsetProp: it would free the node
      node.unlink
      value
    else
      # manually unlink the prop's children if we have live references, so
      # xmlUnsetProp won't free them immediately
      @node.document.unlink_cached_children(prop)
      value if LibXML.xmlUnsetProp(@node, name) == 0
    end
  end
end

class XML::Node
  # PATCH
  # Patch `XML::Node#content` to fix memory leak when getting content of nodes.
  # See: https://github.com/crystal-lang/crystal/issues/16685
  #
  def content : String
    if ptr = LibXML.xmlNodeGetContent(self)
      begin
        String.new(ptr)
      ensure
        LibXML.xmlMemFree(ptr.as(Void*))
      end
    else
      ""
    end
  end

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

  # Adopts a node when crossing document boundaries.
  #
  private def adopt_node(node : Node, from : Document, to : Document)
    if from.@node != to.@node
      result = LibXML.xmlDOMWrapAdoptNode(nil, from.@node.as(LibXML::Doc*), node, to.@node.as(LibXML::Doc*), nil, 0)
      if result != 0
        raise XML::Error.new("xmlDOMWrapAdoptNode failed with code #{result}", 0)
      end
    end
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
  private def move_nodes(node : Node, from : Document, to : Document)
    move_nodes(node.@node, from, to)
  end

  # :ditto:
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

  # ## Text Node Implementation Note ##
  #
  # libxml2 has inconsistent text node merging behavior. Generally,
  # when libxml2 functions (e.g. `xmlAddChild`, `xmlAddNextSibling`,
  # `xmlAddPrevSibling`) add a text node adjacent to another text
  # node, libxml2:
  #
  # 1. Merges the text content into the adjacent node
  # 2. Frees the "added" node's memory
  # 3. Returns a pointer to the merged node
  #
  # ### Important Exceptions ###
  #
  # - `element.add_sibling(text_node)` and `element.add_child(text_node)`:
  #   When the **reference node** (the node calling the method) is an
  #   element, adding a text node does not trigger merging even if an
  #   **adjacent node** is a text node. The **reference node** must be
  #   a text node to trigger merging.
  #
  # - `xmlReplaceNode(old, text_node)`: Never merges, even when replacing
  #   an element between two adjacent text nodes.
  #
  # This behavior is **context-dependent** and **poorly documented**.
  # The same function can either merge or not merge depending on the
  # function called and type of the adjacent node. This makes it difficult
  # to write safe library code without defensive measures.
  #
  # ### Placeholder Elements ###
  #
  # To normalize this, we use temporary placeholder elements when
  # adding text nodes:
  #
  # 1. Create a temporary placeholder element (`<__libxml_ext_placeholder__/>`)
  # 2. Add the placeholder using libxml2 functions
  # 3. Replace the placeholder with the text node using `xmlReplaceNode()`
  #
  # Neither step 2 nor step 3 trigger text node merging.
  #
  # ### Methods Using This Technique
  #
  # - `add_child(text_node)`
  # - `add_sibling(text_node)`

  # Creates a placeholder element.
  #
  private def create_placeholder_element : Node
    placeholder_doc = XML.parse("<__libxml_ext_placeholder__/>")
    placeholder_doc.first_element_child.not_nil!
  end

  # Adds a child node to this node after any existing children.
  #
  # Returns the child node.
  #
  def add_child(child : Node)
    if child.text?
      placeholder = create_placeholder_element
      add_child(placeholder)
      placeholder.replace_with(child)
    else
      from_doc = child.document
      to_doc = self.document
      child.unlink
      adopt_node(child, from_doc, to_doc)
      if LibXML.xmlAddChild(self, child)
        move_nodes(child, from_doc, to_doc)
      else
        raise XML::Error.new("xmlAddChild failed", 0)
      end
    end
    child
  end

  # Replaces this node with the other node.
  #
  # Returns the other node.
  #
  def replace_with(other : Node)
    from_doc = other.document
    to_doc = self.document
    other.unlink
    adopt_node(other, from_doc, to_doc)
    if LibXML.xmlReplaceNode(self, other)
      self.document.unlinked_nodes.add(self.@node)
      move_nodes(other, from_doc, to_doc)
    else
      raise XML::Error.new("xmlReplaceNode failed", 0)
    end
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
    if sibling.text?
      placeholder = create_placeholder_element
      add_sibling(placeholder, position)
      placeholder.replace_with(sibling)
    else
      from_doc = sibling.document
      to_doc = self.document
      sibling.unlink
      adopt_node(sibling, from_doc, to_doc)
      case position
      in Position::After
        unless LibXML.xmlAddNextSibling(self, sibling)
          raise XML::Error.new("xmlAddNextSibling failed", 0)
        end
      in Position::Before
        unless LibXML.xmlAddPrevSibling(self, sibling)
          raise XML::Error.new("xmlAddPrevSibling failed", 0)
        end
      end
      move_nodes(sibling, from_doc, to_doc)
    end
    sibling
  end
end
