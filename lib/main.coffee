_ = require 'underscore-plus'
{Point, Range} = require 'atom'
gpg = require './gpg'

module.exports =
  config:
    gpgExecutable:
      type: 'string'
      default: ''
    gpgHomeDir:
      type: 'string'
      default: ''
    gpgRecipients:
      type: 'string'
      default: ''
    gpgRecipientsFile:
      type: 'string'
      default: ''

  activate: ->
    console.log 'activate gpg'
    atom.commands.add 'atom-text-editor',
      'atom-gpg:encrypt-selections': => @run gpg.encrypt
      'atom-gpg:decrypt-selections': => @run gpg.decrypt

  indentRows: (start, end, level, skipFirstRow) ->
    row = start.row
    if skipFirstRow
      row += 1
    while row < end.row
      @editor.setIndentationForBufferRow row, level
      row++

  handleText: (range, text, type) ->
    if not text
      return false

    if type == 'encrypt' and 'source.yaml' in @rootScopes
      s = range.start
      r = [[s.row, s.column-4], [s.row, s.column]]
      t = @editor.getTextInBufferRange(r)
      if ':' in t
        text = '|\n' + text


    @editor.setTextInBufferRange range, text

    if type == 'encrypt' and 'source.yaml' in @rootScopes
      multiLine = text.split /[\n\r]/
      lines = multiLine.length
      indentLevel = @editor.indentationForBufferRow(range.start.row)
      tabLength = @editor.getTabLength()
      @indentToColumn = false
      if @indentToColumn
        indentLevelNew = range.start.column / tabLength
      else
        indentLevelNew = indentLevel + 1
      rangeEnd = new Point(range.end.row + lines, range.end.column)
      @indentRows range.start, rangeEnd, indentLevelNew, text[0] == '|'


  bufferSetText: (idx, text) ->
    if @buffer[idx]
      @buffer[idx] += text
    else
      @buffer[idx] = text

  setSelections: (returnCode, type) ->
    @rangeCount--

    if @rangeCount < 1
      # sort by range start point
      sorted = _.values(@ranges).sort (a, b) ->
        a.start.compare(b.start)

      # create a checkpoint so multiple changes are grouped as one rollback
      cp = @editor.getBuffer().createCheckpoint()

      # do changes in reverse order to prevent overlapping
      for point in sorted.reverse()
        i = @startPoints[point.start.toString()]
        @handleText @ranges[i], @buffer[i], type
      @editor.getBuffer().groupChangesSinceCheckpoint(cp)

  run: (func) ->
    @selectionIndex = 0
    @startPoints = {}
    @ranges = {}
    @buffer = {}

    @editor = atom.workspace.getActiveTextEditor()
    @rootScopes = @editor.getRootScopeDescriptor()?.getScopesArray()
    @rootScopes ?= @editor.getRootScopeDescriptor()

    allSelectionRanges = @editor.getSelectedBufferRanges()
    @selectedRanges = _.reject allSelectionRanges, (s) -> s.start.isEqual(s.end)
    @rangeCount = @selectedRanges.length

    for range in @selectedRanges
      @ranges[@selectionIndex] = range
      @startPoints[range.start.toString()] = @selectionIndex
      text = @editor.getTextInBufferRange(range)
      if 'source.yaml' in @rootScopes and text[0] == '|'
        start = text.indexOf '-'
        text = text[start..-1]
      console.log range
      bufferedRead = (idx, txt) =>
        output = txt
        @bufferSetText idx, output
      exit_cb = (code, type) =>
        @setSelections code, type

      func text, @selectionIndex, bufferedRead, exit_cb

      @selectionIndex++
