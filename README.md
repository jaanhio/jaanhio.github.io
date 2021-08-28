This page is built using [Hugo](https://gohugo.io/) and deployed on GH Pages with Cloudflare.

Note: 
- CNAME file has to be added to the `/static` directory in order for github to register the custom domain. Else, it will be removed on every new deploy.
- using `hugo --minify` messes up the generated javascript files

## Development

When doing development work (e.g creating new post), hugo can be used to serve the static files. Include `-D` flag if you want to include draft pages
```
hugo server
```

However, some changes such as overriding of CSS styles via `/static/style.css` will not be reflected properly when using `hugo server`.

One way to verify is to build the pages and serve the files separately. [http-server](https://www.npmjs.com/package/http-server) can be used for such use case.

Build pages. Include `-D` flag if you want to include draft pages.
```
hugo
```
The pages will be saved in `./public` directory.

Start `http-server` in same directory. By default, `http-server` will serve files located in the `./public` directory.
```
http-server -c-1 -d -p 8080
```

Improvements:
- Implement pagination on collections page
- Shift images to image hosting service