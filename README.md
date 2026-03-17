# SDML - Server-Side Declarative Markup Language 

--

- This is a backend language that is essentially a language all its own for server-side operations that can be connected to via HTTP direct API calls for user defined API requests to be executed. SDML does not return generated web content in the form of HTML or JavaScript. It returns pure JSON data after executing backend operations like database modifications or other server-side operations.

- more on qhtml6 can be found here: https://github.com/qhtml/qhtml6

- SDML generally speaking uses qhtml-style syntax to define server-side operations in a declarative way.

# example server.sdml :

server { 
 listen { 
   ip {  127.0.0.1 }
   port { 6221 }
 }

 location {
  url { /api/test }
  parameters {
    name 
    message
  }
 accept { GET POST }
  headers {
    Access-Control-Allow-CORS { https://whatever.com }
  }
  property name
  property message
  onRequest { 
    this.name = sanitize(request.name)
    this.message = sanitize(request.message)
    return { hello ${this.name} we received your message: ${this.message}. }
  }


 }
}

sdml can be written in any language as long as that language is sufficiently capable of being able to sanitize data securely and can generate runtime 
instruction based on abstract sdml language (which there is no interpreter for currently) and the language is capable of securely receiving HTTP GET, 
POST, OTHER requests, listening on interfaces/ports, and deducing URLS based on the sdml provided in a single file possibly for multiple interfaces 
running many different servers. Also must support parallel processing using separate threads so that its not super slow.

qhtml6 uses javascript as the primary parser language, which works well but is fragile and easily manipulated. Still, it may be a potential language to be used due to ease of implementation, but other languages are also possible. 

As long as the above example works 100% as-is and can exist in a separate .sdml file and somehow be loaded via whatever host language is used and the instructions in that sdml file are the source of truth for the behavior of the host language, then its fine. 

There are no workarounds allowed anywhere in this codebase. It is purely framework for building new systems on top of not necessarily a final product. 

## Implemented v1 Framework

The repository now contains a modular Node.js framework implementing the above SDML behavior:

- `modules/sdml-parser`: parses SDML and validates scope/semantic rules.
- `modules/sdml-runtime`: runs validated AST as HTTP JSON APIs with sandboxed AST-based execution.
- root module: CLI/integration wiring only (`sdml run --file <path>`).
- `headers { Header-Name { value } }` blocks are supported at server and location scope and are applied to HTTP responses.

### Run

```bash
node bin/sdml.js run --file ./server.sdml --port 6221 --threads 2
```

### Response format

Single-shape pure JSON response only:
- `result`: rendered response string
- `properties`: final request-scope property values
