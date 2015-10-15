_           = require 'lodash'
Busboy      = require 'busboy'
DataSource  = require('loopback-datasource-juggler').DataSource
debug       = require('debug') 'loopback:storage:mongo'
Grid        = require 'gridfs-stream'
mongodb     = require 'mongodb'

GridFS      = mongodb.GridFS
ObjectID    = mongodb.ObjectID

generateUrl = (options) ->
  host      = options.host or options.hostname or 'localhost'
  port      = options.port or 27017
  database  = options.database or 'test'
  if options.username and options.password
    return "mongodb://#{options.username}:#{options.password}@#{host}:#{port}/#{database}"
  else
    return "mongodb://#{host}:#{port}/#{database}"

class MongoStorage
  constructor: (@settings) ->
    if not @settings.url
      @settings.url = generateUrl @settings

  connect: (callback) ->
    self = @
    if @db
      process.nextTick ->
        if callback
          callback null, self.db
    else
      mongodb.MongoClient.connect @settings.url, @settings, (err, db) ->
        if not err
          debug 'Mongo connection established: ' + self.settings.url
          self.db = db
        if callback
          callback err, db

  getContainers: (callback) ->
    @db.collection 'fs.files'
    .find
      'metadata.mongo-storage': true
    .toArray (err, files) ->
      return callback err, files

  getContainer: (name, callback) ->
    @db.collection 'fs.files'
    .findOne
      metadata:
        'mongo-storage': true
        container: name
    , callback

  upload: (container, req, res, callback) ->
    self = @
    busboy = new Busboy headers: req.headers
    busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      options =
        filename: filename
        metadata:
          'mongo-storage': true
          container: container
          filename: filename
          mimetype: mimetype
      self.uploadFile container, file, options
    busboy.on 'finish', ->
      callback()
    req.pipe busboy

  uploadFile: (container, file, options, callback = (-> return)) ->
    options._id = new ObjectID()
    options.mode = 'w'
    gfs = Grid @db, mongodb
    stream = gfs.createWriteStream options
    stream.on 'close', -> callback()
    file.pipe stream


MongoStorage.prototype.getContainers.shared = true
MongoStorage.prototype.getContainers.accepts = []
MongoStorage.prototype.getContainers.returns = {arg: 'containers', type: 'array', root: true}
MongoStorage.prototype.getContainers.http = {verb: 'get', path: '/'}

MongoStorage.prototype.getContainer.shared = true
MongoStorage.prototype.getContainer.accepts = [{arg: 'container', type: 'string'}]
MongoStorage.prototype.getContainer.returns = {arg: 'containers', type: 'object', root: true}
MongoStorage.prototype.getContainer.http = {verb: 'get', path: '/:container'}

MongoStorage.prototype.upload.shared = true
MongoStorage.prototype.upload.accepts = [
  {arg: 'container', type: 'string'}
  {arg: 'req', type: 'object', http: {source: 'req'}}
  {arg: 'res', type: 'object', http: {source: 'res'}}
]
MongoStorage.prototype.upload.returns = {arg: 'result', type: 'object'}
MongoStorage.prototype.upload.http = {verb: 'post', path: '/:container/upload'}

exports.initialize = (dataSource, callback) ->
  settings = dataSource.settings or {}
  connector = new MongoStorage settings
  dataSource.connector = connector
  dataSource.connector.dataSource = dataSource
  connector.DataAccessObject = -> return
  for m, method of MongoStorage.prototype
    if _.isFunction method
      connector.DataAccessObject[m] = method.bind connector
      for k, opt of method
        connector.DataAccessObject[m][k] = opt
  connector.define = (model, properties, settings) -> return
  if callback
    dataSource.connector.connect callback
  return
