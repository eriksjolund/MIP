# Command line interface

MIP uses [MooseX::App](https://metacpan.org/pod/MooseX::App) to create a single command line interface (CLI) entry point to all MIP related processes. The main application is called by:

```Bash
$ mip
```

This will show the usage, global parameters and all available commands and subcommands.
There is currently two main commands:
- Installation
  - rare_disease
- Analyse
  - rare_disease
  - rna
  - cancer

There are three levels of parameters:
- Global
- Commands
- Subcommands

These parameters are defined for the CLI at each level of the underlying namespace in `lib/MIP/Cli`. The complete parameter feature is defined for each command and subcommand in definition file located under `definitions`.

A parameter that is unique to a command or subcommand should only be defined once in that namespace and corresponding definitions file.

A parameter that is shared by all subsequent processes only needs to be defined in the parent namespace and corresponding definitions file.