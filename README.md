# webgl-metal-cap

Capture a local WebGL workload as an Xcode `.gputrace` on Apple silicon.
It builds a small, dedicated WebKit MiniBrowser once; the page still renders
with WebGL, while a tiny invisible WebGPU submission enables WebKit to save the
same underlying Metal work as an offline trace. It does not modify Chrome or
attach a live debugger.

## Setup once

```zsh
./bootstrap-webkit.command
./doctor.command
```

## Run and capture

```zsh
./run.command
```

In a second terminal:

```zsh
./capture.command 3
```

The command prints the saved trace path. Open it with:

```zsh
open -a Xcode /path/to/capture.gputrace
```
