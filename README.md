# Odin Sample

This project is just me trying out [Odin](https://odin-lang.org).

## Compile & Run

```sh
$ odin run src -vet -- <EXPRESSION>
```

On Linux you can provide a file as input:
```sh
$ odin run src -vet -- "$(cat example.txt)"
```

To output numbers only, `sed` can be used as follows:
```sh
| sed -E 's/\s*([+\-]?[0-9]+\.?[0-9]*)\s*=.*/\1/'
```
