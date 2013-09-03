Cargoship
===

Cargoship is a server-block which interacts with seaport(http://github.com/substack/seaport). 
Within your cargoship you can easily add some heavy duties on the server block.

Interface is designed to be similar to express.js.

Usage
---

``` coffeescript
cargoship = require 'cargoship'
ship = cargoship()
ship.use (m) -> m.end()
ship.launch 'role@semver', seaport-address
```
