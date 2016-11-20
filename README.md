# Skeleton

CS4032 Lab3: a tcp socket chat server implementing a specific protocol

## Prerequisites
Elixir v1.4-dev at least
they don't have that packaged yet so you'll need to build from source

to get this running on a fresh digital ocean droplet I merely:
installed erlang:
```bash
sudo apt-get install erlang
```

then cloned and ran the elixir make as outlined [here](http://elixir-lang.org/install.html):
```bash
git clone https://github.com/elixir-lang/elixir.git && cd elixir
```
```bash
make clean test
```
if all the tests pass you'll have a juicy bit of bleeding edge elixir at your fingertips, add the executables to your path:
```bash
export PATH="$PATH:/path/to/where/you/cloned/elixir/bin"
```

to get it working on macOS where I already had elixir + erlang installed, I merely:
removed the stable elixir:
```bash
brew uninstall elixir
```

and then did the clone/make/path steps above


## Installation
Start the server:
```bash
./start.sh 5000
```

Then talk to it.
