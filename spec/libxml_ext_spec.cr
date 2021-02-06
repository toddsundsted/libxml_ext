require "./spec_helper"

Spectator.describe "LibXML2 extensions" do
  let(parent) { XML.parse("<parent/>").first_element_child.not_nil! }
  let(child) { XML.parse("<child/>").first_element_child.not_nil! }
  let(other) { XML.parse("<other/>").first_element_child.not_nil! }

  it "adds a child" do
    parent.add_child(child)
    expect(parent.xpath_node("/parent/child")).to eq(child)
  end

  it "replaces a node" do
    parent.add_child(child).replace_with(other)
    expect(parent.xpath_node("//child")).to be_nil
    expect(parent.xpath_node("/parent/other")).to eq(other)
  end

  it "adds a sibling after the node" do
    parent.add_child(child).add_sibling(other, position: :after)
    expect(parent.xpath_node("/parent/child/following-sibling::other")).to eq(other)
  end

  it "adds a sibling before the node" do
    parent.add_child(child).add_sibling(other, position: :before)
    expect(parent.xpath_node("/parent/child/preceding-sibling::other")).to eq(other)
  end
end
