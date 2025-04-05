# Odin Sample

This project is just me trying out [Odin](https://odin-lang.org).

## Compile & Run

```sh
$ odin build src -vet
$ ./src.bin -- <EXPRESSION>
```

On Linux you can provide a file as input:
```sh
$ ./src.bin -- "$(cat example.txt)"
```

To output numbers only, `sed` can be used as follows:
```sh
| sed -E 's/\s*([+\-]?[0-9]+\.?[0-9]*)\s*=.*/\1/'
```
