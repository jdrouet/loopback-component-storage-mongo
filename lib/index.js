var DataSource, GridFS, MongoStorage, ObjectID, _, debug, generateUrl, mongo;

_ = require('lodash');

DataSource = require('loopback-datasource-juggler').DataSource;

debug = require('debug')('loopback:storage:mongo');

mongo = require('mongodb');

GridFS = mongo.GridFS;

ObjectID = mongo.ObjectID;

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
      return mongo.MongoClient.connect(this.settings.url, this.settings, function(err, db) {
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
      metadata: {
        'mongo-storage': true
      }
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

  MongoStorage.prototype.upload = function(container, file, options, callback) {
    var gridstore, metadata;
    metadata = {
      'mongo-storage': true,
      container: container,
      filename: file
    };
    gridstore = new GridStore(this.db, new ObjectID(), file.name, 'w', {
      metadata: metadata
    });
    return gridstore.open(function(err, gridstore) {
      if (err) {
        return callback(err);
      }
      return gridstore.close(callback);
    });
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
