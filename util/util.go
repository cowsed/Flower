package util

import (
	"fmt"
	"strings"
)

type SourceError interface {
	SourceError(src []rune) string
}

type Range struct {
	Lo, Hi int
}

func (r Range) Length() int {
	return r.Hi - r.Lo
}

func (r *Range) Add(b Range) {
	r.Lo = min(r.Lo, b.Lo)
	r.Hi = max(r.Hi, b.Hi)
}

func HighlightedLine(src []rune, where Range) string {
	line_num := strings.Count(string(src[0:where.Lo]), "\n")
	line_num_text := fmt.Sprintf("%d |", line_num)

	to_start := HowFarToPrevLine(src, where.Lo) - 1
	to_end := HowFarToNextLine(src, where.Hi)
	line := line_num_text + string(src[where.Lo-to_start:where.Hi+to_end])
	line += "\n" + strings.Repeat(" ", to_start+len(line_num_text)) + strings.Repeat("^", where.Length())
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

type Stack[T any] struct {
	underlying []T
}

func (s *Stack[T]) Push(val T) {
	s.underlying = append(s.underlying, val)
}

func (s *Stack[T]) Pop() T {
	var v T = s.underlying[len(s.underlying)-1]
	s.underlying = s.underlying[:len(s.underlying)-1]
	return v
}

func (s *Stack[T]) Peek() T {
	var v T = s.underlying[len(s.underlying)-1]
	return v
}

func (s Stack[T]) Size() int {
	return len(s.underlying)
}
func (s Stack[T]) Reversed() []T {
	sl := make([]T, s.Size())
	for i, t := range s.underlying {
		sl[s.Size()-i-1] = t
	}
	return sl
}
