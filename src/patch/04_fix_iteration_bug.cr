# Patch XML::Node#content= to fix iteration bug that leaks nodes
# https://github.com/crystal-lang/crystal/issues/16419
{% if compare_versions(Crystal::VERSION, "1.19.0") < 0 %}
  class XML::Node
    def content=(content)
      if content.includes?('\0')
        raise ArgumentError.new("cannot include null byte")
      end

      if fragment? || element? || attribute?
        # libxml will immediately free all the children nodes, while we may have
        # live references to a child or a descendant; explicitly unlink all the
        # children before replacing the node's contents
        child = @node.value.children
        while child
          # save next pointer before unlinking, because xmlUnlinkNode
          # clears it, terminating the iteration
          next_child = child.value.next
          if node = document.cached?(child)
            node.unlink
          else
            document.unlinked_nodes << child
            LibXML.xmlUnlinkNode(child)
          end
          child = next_child
        end
      end

      LibXML.xmlNodeSetContent(self, content)
    end
  end
{% end %}
