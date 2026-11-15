// A numbered document (HTMXObjects' `numbered`) writes the numbers of its
// figures and tables into their captions ("Figure 3: …"), so Typst gives them
// none of its own; otherwise every caption would read "Figure 1: Figure 1: …".
// The figures stay figures, with their captions tagged as captions.
#show figure: set figure(numbering: none)
