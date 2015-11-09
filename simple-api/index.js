var express = require('express');
var request = require('superagent');
var app = new express();

var ZOTERO_BASEURL="http://localhost:1234";
var SESSION_ID="foo-123";


app.get('/', function(req, res, next) {
  if (!req.query.url) {
    return next("ERROR: Must specify url");
  }
  var format = 'ris';
  if (req.query.format) {
    format = req.query.format;
  }
  request
      .post(ZOTERO_BASEURL + "/web")
      .send({"url":req.query.url, "sessionid":SESSION_ID})
      .end(function(err, resp){
        if (err) return next(err);
        request
            .post(ZOTERO_BASEURL + "/export?format=" + format)
            .buffer(true)
            .send(resp.body)
            .end(function(err, resp) {
              if (err) return next(err);
              res.set('Content-Type', resp.get('Content-Type'))
              res.send(resp.text);
            });
      });
});

app.use(function errorHandler(err, req, res, next) {
  res.status(406).send(err);
});
app.listen(2000);
