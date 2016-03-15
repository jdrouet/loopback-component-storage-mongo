_           = require 'lodash'
async       = require 'async'
Busboy      = require 'busboy'
DataSource  = require('loopback-datasource-juggler').DataSource
debug       = require('debug') 'loopback:storage:mongo'
Grid        = require 'gridfs-stream'
mongodb     = require 'mongodb'
Promise     = require 'bluebird'

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
      return callback err if err
      list = _(files)
      .map 'metadata'
      .flatten()
      .map 'container'
      .uniq()
      .map (item) ->
        container: item
      .value()
      callback null, list

  getContainer: (name, callback) ->
    @db.collection 'fs.files'
    .find
      'metadata.mongo-storage': true
      'metadata.container': name
    .toArray (err, files) ->
      return callback err if err
      callback null,
        container: name
        files: files

  destroyContainer: (name, callback) ->
    self = @
    self.getFiles name, (err, files) ->
      return callback err if err
      async.each files, (file, done) ->
        self.removeFileById file._id, done
      , callback

  upload: (container, req, res, callback) ->
    self = @
    busboy = new Busboy headers: req.headers
    promises = []
    busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      promises.push new Promise (resolve, reject) ->
        options =
          filename: filename
          metadata:
            'mongo-storage': true
            container: container
            filename: filename
            mimetype: mimetype
        self.uploadFile container, file, options, (err, res) ->
          return reject err if err
          resolve res
    busboy.on 'finish', ->
      Promise.all promises
      .then (res) ->
        return callback null, res
      .catch callback
    req.pipe busboy

  uploadFile: (container, file, options, callback = (-> return)) ->
    options._id = new ObjectID()
    options.mode = 'w'
    gfs = Grid @db, mongodb
    stream = gfs.createWriteStream options
    stream.on 'close', (metaData) ->
      callback null, metaData
    stream.on 'error', callback
    file.pipe stream

  getFiles: (container, callback) ->
    @db.collection 'fs.files'
    .find
      'metadata.mongo-storage': true
      'metadata.container': container
    .toArray callback
  
  removeFile: (container, filename, callback) ->
    self = @
    self.getFile container, filename, (err, file) ->
      return callback err if err
      self.removeFileById file._id, callback

  removeFileById: (id, callback) ->
    self = @
    async.parallel [
      (done) ->
        self.db.collection 'fs.chunks'
        .remove
          files_id: id
        , done
      (done) ->
        self.db.collection 'fs.files'
        .remove
          _id: id
        , done
    ], callback

  __getFile: (query, callback) ->
    @db.collection 'fs.files'
    .findOne query
    , (err, file) ->
      return callback err if err
      if not file
        err = new Error 'File not found'
        err.status = 404
        return callback err
      callback null, file

  getFile: (container, filename, callback) ->
    @__getFile
      'metadata.mongo-storage': true
      'metadata.container': container
      'metadata.filename': filename
    , callback

  getFileById: (id, callback) ->
    @__getFile _id: id, callback

  __download: (file, res, callback = (-> return)) ->
    gfs = Grid @db, mongodb
    read = gfs.createReadStream
      _id: file._id
    res.set 'Content-Disposition', "attachment; filename=\"#{file.filename}\""
    res.set 'Content-Type', file.metadata.mimetype
    res.set 'Content-Length', file.length
    read.pipe res

  downloadById: (id, res, callback = (-> return)) ->
    self = @
    @getFileById id, (err, file) ->
      return callback err if err
      self.__download file, res, callback

  download: (container, filename, res, callback = (-> return)) ->
    self = @
    @getFile container, filename, (err, file) ->
      return callback err if err
      self.__download file, res, callback

MongoStorage.modelName = 'storage'

MongoStorage.prototype.getContainers.shared = true
MongoStorage.prototype.getContainers.accepts = []
MongoStorage.prototype.getContainers.returns = {arg: 'containers', type: 'array', root: true}
MongoStorage.prototype.getContainers.http = {verb: 'get', path: '/'}

MongoStorage.prototype.getContainer.shared = true
MongoStorage.prototype.getContainer.accepts = [{arg: 'container', type: 'string'}]
MongoStorage.prototype.getContainer.returns = {arg: 'containers', type: 'object', root: true}
MongoStorage.prototype.getContainer.http = {verb: 'get', path: '/:container'}

MongoStorage.prototype.destroyContainer.shared = true
MongoStorage.prototype.destroyContainer.accepts = [{arg: 'container', type: 'string'}]
MongoStorage.prototype.destroyContainer.returns = {}
MongoStorage.prototype.destroyContainer.http = {verb: 'delete', path: '/:container'}

MongoStorage.prototype.upload.shared = true
MongoStorage.prototype.upload.accepts = [
  {arg: 'container', type: 'string'}
  {arg: 'req', type: 'object', http: {source: 'req'}}
  {arg: 'res', type: 'object', http: {source: 'res'}}
]
MongoStorage.prototype.upload.returns = {arg: 'result', type: 'object'}
MongoStorage.prototype.upload.http = {verb: 'post', path: '/:container/upload'}

MongoStorage.prototype.getFiles.shared = true
MongoStorage.prototype.getFiles.accepts = [
  {arg: 'container', type: 'string'}
]
MongoStorage.prototype.getFiles.returns = {arg: 'file', type: 'array', root: true}
MongoStorage.prototype.getFiles.http = {verb: 'get', path: '/:container/files'}

MongoStorage.prototype.getFile.shared = true
MongoStorage.prototype.getFile.accepts = [
  {arg: 'container', type: 'string'}
  {arg: 'file', type: 'string'}
]
MongoStorage.prototype.getFile.returns = {arg: 'file', type: 'object', root: true}
MongoStorage.prototype.getFile.http = {verb: 'get', path: '/:container/files/:file'}

MongoStorage.prototype.removeFile.shared = true
MongoStorage.prototype.removeFile.accepts = [
  {arg: 'container', type: 'string'}
  {arg: 'file', type: 'string'}
]
MongoStorage.prototype.removeFile.returns = {}
MongoStorage.prototype.removeFile.http = {verb: 'delete', path: '/:container/files/:file'}

MongoStorage.prototype.download.shared = true
MongoStorage.prototype.download.accepts = [
  {arg: 'container', type: 'string'}
  {arg: 'file', type: 'string'}
  {arg: 'res', type: 'object', http: {source: 'res'}}
]
MongoStorage.prototype.download.http = {verb: 'get', path: '/:container/download/:file'}

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
