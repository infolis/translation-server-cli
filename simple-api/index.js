var express = require('express');
var request = require('superagent');
var app = new express();

var ZOTERO_BASEURL="http://localhost:1234";
var SESSION_ID="foo-123";

var cache = {};

app.get('/', function(req, res, next) {
  var url = req.query.url;
  if (!url) return next("ERROR: Must specify url");
  var format = req.query.format || 'ris';

  cache[url] = cache[url] || {};
  if (cache[url] && cache[url][format]) {
    var cached = cache[url][format];
    res.statusCode = cached[0];
    res.set('Content-Type',  cached[1]);
    res.send(cached[2]);
    return;
  }
  request
      .post(ZOTERO_BASEURL + "/web")
      .send({"url" : url, "sessionid" : SESSION_ID})
      .end(function(err, resp) {
        if (err) {
          cache[url][doiMode ? 'doi' : format] = [500, 'text/plain', err.toString()];
          return next(err);
        };
        doiMode = format === 'doi';
        if (doiMode) format = 'ris';
        request
            .post(ZOTERO_BASEURL + "/export?format=" + format)
            .buffer(true)
            .send(resp.body)
            .end(function(err, resp) {
              if (err) {
                cache[url][doiMode ? 'doi' : format] = [500, 'text/plain', err.toString()];
                return next(err);
              };
              var contentType = doiMode ? 'text/plain' : resp.headers['content-type'];
              var statusCode = resp.statusCode;
              var text = resp.text;
              if (doiMode) {
                m = resp.text.match(/DO\s+-\s+(.*)/);
                if (! m) {
                  statusCode = 404;
                } else {
                  text = m[1];
                }
                format = 'doi';
              }
              var cached = cache[url][format] = [statusCode, contentType, text];
              res.statusCode = cached[0];
              res.set('Content-Type',  cached[1]);
              res.send(cached[2]);
            });
      });
});

app.use(function errorHandler(err, req, res, next) {
  res.status(406).send(err);
});
app.listen(2000);
