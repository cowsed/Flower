package util

type ParseRecord struct {
	what_happened string
}

func NewParseResult(pr ParseRecord) ParseResult {
	return ParseResult{
		is_error: false,
		err:      nil,
		pr:       pr,
	}
}
func NewParseResultError(se SourceError) ParseResult {
	return ParseResult{
		is_error: true,
		err:      se,
		pr:       ParseRecord{},
	}
}

type ParseResult struct {
	is_error bool
	err      SourceError
	pr       ParseRecord
}
