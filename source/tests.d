module source.tests;

/**
    Contains the main function for running a unittest build, which is generated
    by unit-threaded. Unit tests are built into D but either Dub or the
    compilers don't produce nice reports for them, e.g. which tests passed.

    Most of them (gasp) don't even print results with pretty colours.

    So I'm using unit-threaded for that.

    Unfortunately I have to manually list here all the D source files that have
    unit tests in them... grumble. Grep for 'unittest' and paste the matching
    files in.
*/

import unit_threaded;

mixin runTestsMain!(
    "game",
    "util",
    "units",
);
