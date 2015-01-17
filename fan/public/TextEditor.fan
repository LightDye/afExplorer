using afIoc
using afReflux
using syntax
using gfx
using fwt

** (View) - 
** A text editor with syntax highlighting. Borrowed from [fluxtext]`pod:fluxtext`.
class TextEditor : View {
	@Inject private Registry	registry
	@Inject private Explorer	explorer
	@Inject private Reflux		reflux
	
	** The 'File' being edited.
			File? 				file
	internal TextEditorOptions	options := TextEditorOptions.load
	internal Charset 			charset := options.charset
	internal SyntaxRules? 		rules
	internal RichText? 			richText
	internal TextDoc? 			doc

	private TextEditorController?	controller
	internal FindBar				find
	internal DateTime? 				fileTimeAtLoad
	internal Label 					caretField		:= Label()
	internal Label 					charsetField	:= Label()
	
	@Inject private GlobalCommands	globalCommands
			private	EdgePane		edgePane
	
	protected new make(|This| in) : super(in) {
		find = FindBar(this)
		content = edgePane = EdgePane {
			it.top = buildToolBar
			it.bottom = buildStatusBar
		}
		&wordWrap = explorer.preferences.wordWrap
	}
	
	@NoDoc
	override Void onActivate() {
		super.onActivate
		
		globalCommands["afExplorer.cmdFind"				].addInvoker("afReflux.textEditor", |Event? e|	{ find.showFind } )
		globalCommands["afExplorer.cmdFind"				].addEnabler("afReflux.textEditor", |  ->Bool| 	{ true } )
		globalCommands["afExplorer.cmdFindNext"			].addInvoker("afReflux.textEditor", |Event? e|	{ find.next } )
		globalCommands["afExplorer.cmdFindNext"			].addEnabler("afReflux.textEditor", |  ->Bool| 	{ true } )
		globalCommands["afExplorer.cmdFindPrev"			].addInvoker("afReflux.textEditor", |Event? e|	{ find.prev } )
		globalCommands["afExplorer.cmdFindPrev"			].addEnabler("afReflux.textEditor", |  ->Bool| 	{ true } )
		globalCommands["afExplorer.cmdReplace"			].addInvoker("afReflux.textEditor", |Event? e|	{ find.showFindReplace } )
		globalCommands["afExplorer.cmdReplace"			].addEnabler("afReflux.textEditor", |  ->Bool| 	{ true } )
		globalCommands["afExplorer.cmdGoto"				].addInvoker("afReflux.textEditor", |Event? e|	{ controller?.onGoto(e) } )
		globalCommands["afExplorer.cmdGoto"				].addEnabler("afReflux.textEditor", |  ->Bool| 	{ true } )

		// restore viewport and caret position
//		caretOffset := Actor.locals["fluxText.caretOffset.$resource.uri"]
//		topLine := Actor.locals["fluxText.topLine.$resource.uri"]
//		if (caretOffset != null) richText.caretOffset = caretOffset
//		if (topLine != null) richText.topLine = topLine
		richText?.focus
	}
	
	@NoDoc
	override Void onDeactivate() {
		super.onDeactivate
		
		globalCommands["afExplorer.cmdFind"				].removeInvoker("afReflux.textEditor")
		globalCommands["afExplorer.cmdFind"				].removeEnabler("afReflux.textEditor")
		globalCommands["afExplorer.cmdFindNext"			].removeInvoker("afReflux.textEditor")
		globalCommands["afExplorer.cmdFindNext"			].removeEnabler("afReflux.textEditor")
		globalCommands["afExplorer.cmdFindPrev"			].removeInvoker("afReflux.textEditor")
		globalCommands["afExplorer.cmdFindPrev"			].removeEnabler("afReflux.textEditor")
		globalCommands["afExplorer.cmdReplace"			].removeInvoker("afReflux.textEditor")
		globalCommands["afExplorer.cmdReplace"			].removeEnabler("afReflux.textEditor")
		globalCommands["afExplorer.cmdGoto"				].removeInvoker("afReflux.textEditor")
		globalCommands["afExplorer.cmdGoto"				].removeEnabler("afReflux.textEditor")

		// save viewport and caret position
//		Actor.locals["fluxText.caretOffset.$resource.uri"] = richText.caretOffset
//		Actor.locals["fluxText.topLine.$resource.uri"] = richText.topLine
	}
	
	
	Bool wordWrap {
		set {
			&wordWrap = it
			newWidgets
		}
	}
	
	@NoDoc
	override Void load(Resource resource) {
		super.load(resource)

		file = (resource as FileResource).file

		// load the document into memory
		loadDoc
		charsetField.text = charset.toStr

		newWidgets
	}
	
	private Void newWidgets() {
		// create rich text widget
		richText = RichText { model = doc; border = false; wrap = wordWrap }
		richText.font = options.font
		richText.tabSpacing = options.tabSpacing

		// initialize controller
		controller = registry.autobuild(TextEditorController#, [this])
		controller.register
		controller.updateCaretStatus

		edgePane.center = richText
		edgePane.relayout
		richText.focus
	}

	@NoDoc
	override Void save() {	
		out := file.out { it.charset = this.charset }
		try		doc.save(out)
		finally	out.close
		fileTimeAtLoad = file.modified

		super.save
	}
	
	@NoDoc
	override Bool confirmClose() {
		if (!isDirty) return true
		
		r := Dialog.openQuestion(reflux.window, "Save changes to $resource.name?", [Dialog.yes, Dialog.no, Dialog.cancel])
		if (r == Dialog.cancel) return false
		if (r == Dialog.yes) save

		return true
	}
	
	internal Void loadDoc() {
		// read document into memory, if we fail with the
		// configured charset, then fallback to ISO 8859-1
		// which will always "work" since it is byte based
		lines := readAllLines
		if (lines == null) {
			charset = Charset.fromStr("ISO-8859-1")
			lines	 = readAllLines
		}

		// save this time away to check on focus events
		fileTimeAtLoad = file.modified

		// figure out what syntax file to use
		// based on file extension and shebang
		rules = SyntaxRules.loadForFile(file, lines.first) ?: SyntaxRules()

		// load document
		doc = TextDoc(options, rules)
		doc.load(lines)
	}

	private Str[]? readAllLines() {
		in := file.in { it.charset = this.charset }
		try		return in.readAllLines
		catch	return null
		finally	in.close
	}

	private Widget buildToolBar() {
		return EdgePane {
//			top = InsetPane(4,4,5,4) {
//				ToolBar {
//					addCommand(globalCommands["afReflux.cmdSave"].command)
//					addSep
////					addCommand(frame.command(CommandId.cut))
////					addCommand(frame.command(CommandId.copy))
////					addCommand(frame.command(CommandId.paste))
////					addSep
////					addCommand(frame.command(CommandId.undo))
////					addCommand(frame.command(CommandId.redo))
//				},
//			}
			bottom = find
		}
	}

	private Widget buildStatusBar() {
		return GridPane {
			it.numCols = 2
			it.hgap = 10
			it.halignPane = Halign.right
			it.add(caretField)
			it.add(charsetField)
		}
	}
}
