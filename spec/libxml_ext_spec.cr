require "./spec_helper"

class XML::Node
  getter node
end

class XML::Document < XML::Node
  getter cache
  getter unlinked_nodes
end

Spectator.describe "LibXML2 extensions" do
  context "creating a text node" do
    it "rejects text with null byte" do
      expect { XML::Node.new("foo\0bar") }.to raise_error(ArgumentError, /null byte/)
    end

    context "with valid text" do
      subject { XML::Node.new("foo bar") }

      it "is a text node" do
        expect(subject.type).to eq(XML::Node::Type::TEXT_NODE)
      end

      it "has the text" do
        expect(subject.text).to eq("foo bar")
      end

      it "sets its document" do
        expect(subject.document).to be_a(XML::Document)
      end

      it "adds itself as a child of its document" do
        expect(subject.document.children).to contain_exactly(subject)
      end

      it "adds itself to its document's cache" do
        expect(subject.document.cache.keys).to have(subject.node)
      end
    end
  end

  context "creating a text node" do
    let(doc) { XML.parse("<root/>") }

    it "rejects text with null byte" do
      expect { doc.create_text_node("foo\0bar") }.to raise_error(ArgumentError, /null byte/)
    end

    context "with valid text" do
      subject { doc.create_text_node("foo bar") }

      it "is a text node" do
        expect(subject.type).to eq(XML::Node::Type::TEXT_NODE)
      end

      it "has the text" do
        expect(subject.text).to eq("foo bar")
      end

      it "sets its document" do
        expect(subject.document).to eq(doc)
      end

      it "adds itself to the document's cache" do
        expect(doc.cache).to have_key(subject.node)
      end

      let(root) { doc.first_element_child.not_nil! }

      it "is not a child of the document" do
        expect(root.children).not_to contain(subject)
      end

      context "after insertion" do
        before_each { root.add_child(subject) }

        it "is a child of the document" do
          expect(root.children).to contain_exactly(subject)
        end
      end
    end
  end

  context "adding a child node" do
    let(parent) { XML.parse("<parent/>").first_element_child.not_nil! }
    let(node) { XML.parse("<node/>").first_element_child.not_nil! }

    def operation
      parent.add_child(node)
    end

    it "adds the child to the parent" do
      expect { operation }.to change { parent.xpath_node("/parent/node") }.from(nil).to(node)
    end

    it "changes the child's document" do
      expect { operation }.to change { node.document }.from(node.document).to(parent.document)
    end

    let!(node_doc) { node.document }
    let!(parent_doc) { parent.document }

    it "removes the child from the child document's cache" do
      expect { operation }.to change { node_doc.cache.size }.by(-1)
    end

    it "adds the child to the parent document's cache" do
      expect { operation }.to change { parent_doc.cache.size }.by(1)
    end

    post_condition do
      expect(node_doc.unlinked_nodes).not_to have(node.node)
      expect(parent_doc.unlinked_nodes).not_to have(node.node)
    end

    context "when child was already added elsewhere" do
      let(other) { XML.parse("<other/>").first_element_child.not_nil! }

      before_each { parent.add_child(node) }

      def operation
        other.add_child(node)
      end

      it "removes the child from the original parent" do
        expect { operation }.to change { parent.xpath_node("//node") }.from(node).to(nil)
      end

      it "adds the child to the other parent" do
        expect { operation }.to change { other.xpath_node("/other/node") }.from(nil).to(node)
      end

      it "changes the child's document" do
        expect { operation }.to change { node.document }.from(parent.document).to(other.document)
      end

      let!(other_doc) { other.document }

      it "removes the child from the parent document's cache" do
        expect { operation }.to change { parent_doc.cache.size }.by(-1)
      end

      it "adds the child to the other document's cache" do
        expect { operation }.to change { other_doc.cache.size }.by(1)
      end

      post_condition do
        expect(other_doc.unlinked_nodes).not_to have(node.node)
      end
    end

    context "given a subtree" do
      let(other) { XML.parse("<other/>").first_element_child.not_nil! }

      before_each { parent.add_child(node) }

      def operation
        other.add_child(parent)
      end

      it "adds the child to the parent" do
        expect { operation }.to change { other.xpath_node("/other/parent/node") }.from(nil).to(node)
      end

      it "changes the child's document" do
        expect { operation }.to change { node.document }.from(parent.document).to(other.document)
      end

      let!(other_doc) { other.document }

      it "removes the child from the parent document's cache" do
        expect { operation }.to change { parent_doc.cache.size }.by(-2)
      end

      it "adds the child to the other document's cache" do
        expect { operation }.to change { other_doc.cache.size }.by(2)
      end

      post_condition do
        expect(other_doc.unlinked_nodes).not_to have(node.node)
      end
    end

    context "given a text node" do
      let(text) { XML::Node.new("text") }

      def operation
        parent.add_child(text)
      end

      it "adds the text node to the parent" do
        expect { operation }.to change { parent.xpath_node("/parent/text()") }.from(nil).to(text)
      end

      it "changes the text node's document" do
        expect { operation }.to change { text.document }.from(text.document).to(parent.document)
      end

      let!(text_doc) { text.document }
      let!(parent_doc) { parent.document }

      it "removes the text node from the text node document's cache" do
        expect { operation }.to change { text_doc.cache.has_key?(text.node) }.from(true).to(false)
      end

      it "adds the text node to the parent document's cache" do
        expect { operation }.to change { parent_doc.cache.has_key?(text.node) }.from(false).to(true)
      end

      post_condition do
        expect(text_doc.unlinked_nodes).not_to have(text.node)
        expect(parent_doc.unlinked_nodes).not_to have(text.node)
      end
    end
  end

  context "replacing a node" do
    let(parent) { XML.parse("<parent><node/></parent>").first_element_child.not_nil! }
    let(other) { XML.parse("<other/>").first_element_child.not_nil! }
    let(node) { parent.xpath_node("/parent/node").not_nil! }

    def operation
      node.replace_with(other)
    end

    it "removes node from the parent" do
      expect { operation }.to change { parent.xpath_node("/parent/node") }.from(node).to(nil)
    end

    it "adds other to the parent" do
      expect { operation }.to change { parent.xpath_node("/parent/other") }.from(nil).to(other)
    end

    it "does not change the node's document" do
      expect { operation }.not_to change { node.document }
    end

    it "changes the other's document" do
      expect { operation }.to change { other.document }.from(other.document).to(parent.document)
    end

    let!(node_doc) { node.document }
    let!(other_doc) { other.document }
    let!(parent_doc) { parent.document }

    it "does not remove node from the document's cache" do
      expect { operation }.not_to change { node_doc.cache.has_key?(node.@node) }
    end

    it "removes other from other document's cache" do
      expect { operation }.to change { other_doc.cache.size }.by(-1)
    end

    it "adds other to the parent document's cache" do
      expect { operation }.to change { parent_doc.cache.size }.by(1)
    end

    post_condition do
      expect(node_doc.unlinked_nodes).to have(node.node)
      expect(other_doc.unlinked_nodes).not_to have(other.node)
    end

    context "given a text node" do
      let(text) { XML::Node.new("text") }

      def operation
        node.replace_with(text)
      end

      it "replaces node with text" do
        expect { operation }.to change { parent.xpath_node("/parent/child::node()") }.from(node).to(text)
      end
    end
  end

  context "adding a sibling after a node" do
    let(parent) { XML.parse("<parent><node/></parent>").first_element_child.not_nil! }
    let(other) { XML.parse("<other/>").first_element_child.not_nil! }
    let(node) { parent.xpath_node("/parent/node").not_nil! }

    def operation
      node.add_sibling(other, position: :after)
    end

    it "adds other after the node" do
      expect { operation }.to change { parent.xpath_node("/parent/node/following-sibling::other") }.from(nil).to(other)
    end

    it "changes the other's document" do
      expect { operation }.to change { other.document }.from(other.document).to(parent.document)
    end

    let!(other_doc) { other.document }
    let!(parent_doc) { parent.document }

    it "removes other from other document's cache" do
      expect { operation }.to change { other_doc.cache.size }.by(-1)
    end

    it "adds other to the parent document's cache" do
      expect { operation }.to change { parent_doc.cache.has_key?(other.@node) }.from(false).to(true)
    end

    post_condition do
      expect(other_doc.unlinked_nodes).not_to have(other.node)
    end

    context "given a text node" do
      let(text) { XML::Node.new("text") }

      def operation
        node.add_sibling(text, position: :after)
      end

      it "adds text after the node" do
        expect { operation }.to change { parent.xpath_node("/parent/node/following-sibling::text()") }.from(nil).to(text)
      end
    end
  end

  context "adding a sibling before a node" do
    let(parent) { XML.parse("<parent><node/></parent>").first_element_child.not_nil! }
    let(other) { XML.parse("<other/>").first_element_child.not_nil! }
    let(node) { parent.xpath_node("/parent/node").not_nil! }

    def operation
      node.add_sibling(other, position: :before)
    end

    it "adds other before the node" do
      expect { operation }.to change { parent.xpath_node("/parent/node/preceding-sibling::other") }.from(nil).to(other)
    end

    it "changes the other's document" do
      expect { operation }.to change { other.document }.from(other.document).to(parent.document)
    end

    let!(other_doc) { other.document }
    let!(parent_doc) { parent.document }

    it "removes other from other document's cache" do
      expect { operation }.to change { other_doc.cache.size }.by(-1)
    end

    it "adds other to the parent document's cache" do
      expect { operation }.to change { parent_doc.cache.has_key?(other.@node) }.from(false).to(true)
    end

    post_condition do
      expect(other_doc.unlinked_nodes).not_to have(other.node)
    end

    context "given a text node" do
      let(text) { XML::Node.new("text") }

      def operation
        node.add_sibling(text, position: :before)
      end

      it "adds text before the node" do
        expect { operation }.to change { parent.xpath_node("/parent/node/preceding-sibling::text()") }.from(nil).to(text)
      end
    end
  end
end
