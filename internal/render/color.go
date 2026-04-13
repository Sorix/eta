package render

// Color is an ANSI progress bar color.
type Color string

const (
	Green   Color = "green"
	Yellow  Color = "yellow"
	Red     Color = "red"
	Blue    Color = "blue"
	Magenta Color = "magenta"
	Cyan    Color = "cyan"
	White   Color = "white"
)

func (c Color) ansiCode() string {
	switch c {
	case Green:
		return "\x1b[32m"
	case Yellow:
		return "\x1b[33m"
	case Red:
		return "\x1b[31m"
	case Blue:
		return "\x1b[34m"
	case Magenta:
		return "\x1b[35m"
	case Cyan:
		return "\x1b[36m"
	case White:
		return "\x1b[37m"
	default:
		return "\x1b[32m"
	}
}

// BarStyle controls how predicted-only progress is drawn.
type BarStyle int

const (
	Layered BarStyle = iota
	Solid
)
