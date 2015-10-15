var Busboy, DataSource, Grid, GridFS, MongoStorage, ObjectID, _, debug, generateUrl, mongodb;

_ = require('lodash');

Busboy = require('busboy');

DataSource = require('loopback-datasource-juggler').DataSource;

debug = require('debug')('loopback:storage:mongo');

Grid = require('gridfs-stream');

mongodb = require('mongodb');

GridFS = mongodb.GridFS;

ObjectID = mongodb.ObjectID;

generateUrl = function(options) {
  var database, host, port;
  host = options.host || options.hostname || 'localhost';
  port = options.port || 27017;
  database = options.database || 'test';
  if (options.username && options.password) {
    return "mongodb://" + options.username + ":" + options.password + "@" + host + ":" + port + "/" + database;
  } else {
    return "mongodb://" + host + ":" + port + "/" + database;
  }
};

MongoStorage = (function() {
  function MongoStorage(settings1) {
    this.settings = settings1;
    if (!this.settings.url) {
      this.settings.url = generateUrl(this.settings);
    }
  }

  MongoStorage.prototype.connect = function(callback) {
    var self;
    self = this;
    if (this.db) {
      return process.nextTick(function() {
        if (callback) {
          return callback(null, self.db);
        }
      });
    } else {
      return mongodb.MongoClient.connect(this.settings.url, this.settings, function(err, db) {
        if (!err) {
          debug('Mongo connection established: ' + self.settings.url);
          self.db = db;
        }
        if (callback) {
          return callback(err, db);
        }
      });
    }
  };

  MongoStorage.prototype.getContainers = function(callback) {
    return this.db.collection('fs.files').find({
      'metadata.mongo-storage': true
    }).toArray(function(err, files) {
      return callback(err, files);
    });
  };

  MongoStorage.prototype.getContainer = function(name, callback) {
    return this.db.collection('fs.files').findOne({
      metadata: {
        'mongo-storage': true,
        container: name
      }
    }, callback);
  };

  MongoStorage.prototype.upload = function(container, req, res, callback) {
    var busboy, self;
    self = this;
    busboy = new Busboy({
      headers: req.headers
    });
    busboy.on('file', function(fieldname, file, filename, encoding, mimetype) {
      var options;
      options = {
        filename: filename,
        metadata: {
          'mongo-storage': true,
          container: container,
          filename: filename,
          mimetype: mimetype
        }
      };
      return self.uploadFile(container, file, options);
    });
    busboy.on('finish', function() {
      return callback();
    });
    return req.pipe(busboy);
  };

  MongoStorage.prototype.uploadFile = function(container, file, options, callback) {
    var gfs, stream;
    if (callback == null) {
      callback = (function() {});
    }
    options._id = new ObjectID();
    options.mode = 'w';
    gfs = Grid(this.db, mongodb);
    stream = gfs.createWriteStream(options);
    stream.on('close', function() {
      return callback();
    });
    return file.pipe(stream);
  };

  return MongoStorage;

})();

MongoStorage.prototype.getContainers.shared = true;

MongoStorage.prototype.getContainers.accepts = [];

MongoStorage.prototype.getContainers.returns = {
  arg: 'containers',
  type: 'array',
  root: true
};

MongoStorage.prototype.getContainers.http = {
  verb: 'get',
  path: '/'
};

MongoStorage.prototype.getContainer.shared = true;

MongoStorage.prototype.getContainer.accepts = [
  {
    arg: 'container',
    type: 'string'
  }
];

MongoStorage.prototype.getContainer.returns = {
  arg: 'containers',
  type: 'object',
  root: true
};

MongoStorage.prototype.getContainer.http = {
  verb: 'get',
  path: '/:container'
};

MongoStorage.prototype.upload.shared = true;

MongoStorage.prototype.upload.accepts = [
  {
    arg: 'container',
    type: 'string'
  }, {
    arg: 'req',
    type: 'object',
    http: {
      source: 'req'
    }
  }, {
    arg: 'res',
    type: 'object',
    http: {
      source: 'res'
    }
  }
];

MongoStorage.prototype.upload.returns = {
  arg: 'result',
  type: 'object'
};

MongoStorage.prototype.upload.http = {
  verb: 'post',
  path: '/:container/upload'
};

exports.initialize = function(dataSource, callback) {
  var connector, k, m, method, opt, ref, settings;
  settings = dataSource.settings || {};
  connector = new MongoStorage(settings);
  dataSource.connector = connector;
  dataSource.connector.dataSource = dataSource;
  connector.DataAccessObject = function() {};
  ref = MongoStorage.prototype;
  for (m in ref) {
    method = ref[m];
    if (_.isFunction(method)) {
      connector.DataAccessObject[m] = method.bind(connector);
      for (k in method) {
        opt = method[k];
        connector.DataAccessObject[m][k] = opt;
      }
    }
  }
  connector.define = function(model, properties, settings) {};
  if (callback) {
    dataSource.connector.connect(callback);
  }
};
