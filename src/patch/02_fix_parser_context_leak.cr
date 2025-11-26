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
