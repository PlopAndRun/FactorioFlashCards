local _M = {};

_M.MOD_PREFIX = 'flashcards-'

_M.flashcard = {}
_M.flashcard.ITEM = _M.MOD_PREFIX .. 'flashcard'
_M.flashcard.RECIPE = _M.flashcard.ITEM

_M.writer = {}
_M.writer.WRITE_RECIPE = _M.MOD_PREFIX .. 'write-recipe'
_M.writer.BUILDING = _M.MOD_PREFIX .. 'writer'
_M.writer.ITEM = _M.writer.BUILDING
_M.writer.RECIPE = _M.writer.ITEM
_M.writer.SIGNAL_RECEIVER = _M.MOD_PREFIX .. 'writer-signal-receiver'

_M.reader = {}
_M.reader.BUILDING = _M.MOD_PREFIX .. 'reader'
_M.reader.ITEM = _M.reader.BUILDING
_M.reader.RECIPE = _M.reader.BUILDING

return _M;