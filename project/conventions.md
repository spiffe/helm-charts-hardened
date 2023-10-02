<!-- vim: ft=markdown colorcolumn=72
-->
# Development Conventions

This document intends to capture the current coding conventions for
the SPIRE Helm Chart project, permitting multiple developers to align
to a similar style and standard when offering their contributions.

It is impossible to describe every scenario a developer might encounter,
likewise it is equally impossible to describe the best choice to make
under all future circumstances.  For this reason, many conventions also
have a small explanation of the rationale behind the guidance, allowing
future development efforts to weigh and balance the conflicting forces
in ambiguous situations not clearly covered.

This document is intended to be a living document.  If you have an issue
with a convention, we hope that you will create an issue describing the
problem, and a pull request suggesting the update.  By addressing the
convention, we hope to avoid arguments about conventions in the pull
request review process, which slow the process and are often subject to
the popular whims of the moment.

## Conventions used in this document

While this is not a software specification, the key words "MUST",
"MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED",  "MAY", and "OPTIONAL" in this document are to be
interpreted as closely to the convention as it would be to a
specification described in RFC 2119.

Use of the word in its non-all caps form SHOULD NOT be interpreted in
the strict definitions user RFC 2119, but SHOULD be interpreted in
context with a meaning aligned to RFC 2119.

## Helm Chart conventions

Helm values are organized in a tree structure, with each entry having
a key, the path within the structure, and a value, the contents held
at that path.  Some of the contents include objects and arrays, which
are structures that permit multiple values under a particular path.

This design choice mimics the representation of a file system, and we
may use file system analogies to describe the conventions and choices
in the project.

### Preference for absolute paths in templates

Outside of looping constructs that require relative paths, templates
should use absolute paths (paths starting with the `.` character) for
their value references.  

### Helm Key path elements

Elements refer to items in the configuration.  Some of those items are
external to the project, while others are components the project choose
to implement the Helm Chart packaging solution.

### Preferred characters for helm path elements

Elements within a helm chart path SHOULD limit the use of special
characters, even when such characters are supported by Helm.  ASCII
letters, upper and lower case, ASCII numerals, and the ASCII underscore
character are always permitted.  

Other characters, such as `@`, `~`, `&`, `+` are often used as
shorthand to represent, respectively `at`, `similar / not`, 
`minus / without`, `and / reference`, `plus / with`.  Helm key elements
MUST NOT contain such symbols, as it burdens the reader to deduce the
intent of the writer.

`-` SHOULD NOT be used when there are good alternatives. Its reasonable
to use when spire itself uses it for config such as plugin names or
required by helm for child charts.

### Camel Case for created elements

Elements that refer to components that the project has created should
exclusively use camel case, with a the first word being lower case.  To
illustrate, a "card sort order" path element would read "cardSortOrder".

### Exact Case for non-created elements

Elements that reflect components that have well known names should make
every effort to use the well known name exactly, even if the rules for
captialization don't follow other naming conventions.  Exceptions to
this SHOULD include replacing problematic characters with underscores,
to improve template functionality.  To illustrate, the operating system 
NeXTSTEP would read as "NeXTSTEP" and "NeXT Computers" SHOULD be written
as "NeXT_Computers" but may also be written as "NeXTComputers" if clarity
is maintained.

### Acronyms and Minimalists

Occasionally the use of an Acronym or Minimalist is used as part of an
element name.  An acronym is the use of the first letter of a phrase
or multi-word proper name that is pronounceable, while an initialisim is
the use of the first letter of a phrase or multi-word proper name 
pronounced by naming the letters.  `NASA` is an example of an acronym,
while `NFL` is an example of an Initialisim.

To keep the recognition of the Acronym or Initialisim, an all capital
representation of the Acronym or Initialisim MUST be maintained.  To
reduce the confusion this can create in camel case elements, we recommend
that such Acronyms and Initialisim be placed at the end of the element
or the element is restructured to avoid confusion.  For example, 
`mailingListNASA` or `mailingList.NASA` is preferred over
`NASAMailingList`.

Acronyms and Initialisim occasionally use periods in their presentation.
When they do, the periods MUST be removed without replacement by
another character.  To illustrate `U.N.` for the United Nations should
be written as `UN`.

### Abbreviations

Abbreviations shorten words by using some of the letters of the original
word.  In all cases, element names that contain parts which are
abbreviations should be represented in the case determined by the part's
position.  For example, a Junior administrator, should be written as
`jrAdmin`.

Abbreviations occasionally use periods in their presentation.  When they
do, the periods MUST be removed without replacement by another character.
To illustrate, use `acctSchedule` for Acct. Schedule.
