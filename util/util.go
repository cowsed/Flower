package util

import "strings"

type Range struct {
	Lo, Hi int
}

func (r Range) Length() int {
	return r.Hi - r.Lo
}

func HighlightedLine(src []rune, where Range) string {
	to_start := HowFarToPrevLine(src, where.Lo)
	to_end := HowFarToNextLine(src, where.Hi)
	line := string(src[where.Lo-to_start : where.Hi+to_end])
	line += "\n" + strings.Repeat(" ", to_start-1) + strings.Repeat("^", where.Length())
	return line

}

func HowFarToPrevLine(src []rune, start int) int {
	count := 0
	for src[start-count] != '\n' {
		count++
		if start-count <= 0 {
			break
		}
	}
	return count
}

func HowFarToNextLine(src []rune, start int) int {
	count := 0
	for src[start+count] != '\n' {
		count++
		if start+count == len(src) {
			break
		}
	}
	return count
}
