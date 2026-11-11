# HTMXObjects.jl

HTMXObjects turns Julia objects into HTTP routes that return HTML pages, fragments and Markdown.

```sh
git clone -b devibe https://github.com/nsiccha/HTMXObjects.jl
cd HTMXObjects.jl
julia --project=. test/provision.jl
```

```@example start
using HTMXObjects
@htmx struct Greeting
    @get index(; name::String="Ada") = h.p("Hello, $name.")
end
route!(Greeting(); prefix="/greeting");
response = dispatch(:GET, "/greeting/?name=Lin");
@assert response.status == 200 # hide
Base.HTML(String(response.body))
```

The query supplies `name`; the route returns the paragraph shown above.
`dispatch` uses the in-process router, so this example needs no listening server.

## Server

Save the Julia block as `greeting.jl`. To listen on localhost, run this shell
command from the checkout. Installation and listening are shell instructions;
the documentation build already has its environment and does not start a server.

```sh
julia --project=. -L greeting.jl -e 'serve(; host="127.0.0.1", port=8080)'
```

Open `http://127.0.0.1:8080/greeting/?name=Lin` in a browser.
The provisioning command supplies the unregistered dependencies used by this
source revision. Keep the resulting environment when running the examples.

## Reading paths

[Objects and routes](guides/objects.md) explains the lifetime of an object and
its requests. [Forms](guides/forms.md) adds typed query and body parameters.
The [sample browser](examples/sample-browser.md) combines data, routing,
rendered output and response checks in one application.

The [route reference](reference/routes.md) documents registration and dispatch;
the other Reference pages group the exported API by task.
