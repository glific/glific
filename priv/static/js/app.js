/******/ (function(modules) { // webpackBootstrap
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId]) {
/******/ 			return installedModules[moduleId].exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			i: moduleId,
/******/ 			l: false,
/******/ 			exports: {}
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.l = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	// expose the modules object (__webpack_modules__)
/******/ 	__webpack_require__.m = modules;
/******/
/******/ 	// expose the module cache
/******/ 	__webpack_require__.c = installedModules;
/******/
/******/ 	// define getter function for harmony exports
/******/ 	__webpack_require__.d = function(exports, name, getter) {
/******/ 		if(!__webpack_require__.o(exports, name)) {
/******/ 			Object.defineProperty(exports, name, { enumerable: true, get: getter });
/******/ 		}
/******/ 	};
/******/
/******/ 	// define __esModule on exports
/******/ 	__webpack_require__.r = function(exports) {
/******/ 		if(typeof Symbol !== 'undefined' && Symbol.toStringTag) {
/******/ 			Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
/******/ 		}
/******/ 		Object.defineProperty(exports, '__esModule', { value: true });
/******/ 	};
/******/
/******/ 	// create a fake namespace object
/******/ 	// mode & 1: value is a module id, require it
/******/ 	// mode & 2: merge all properties of value into the ns
/******/ 	// mode & 4: return value when already ns object
/******/ 	// mode & 8|1: behave like require
/******/ 	__webpack_require__.t = function(value, mode) {
/******/ 		if(mode & 1) value = __webpack_require__(value);
/******/ 		if(mode & 8) return value;
/******/ 		if((mode & 4) && typeof value === 'object' && value && value.__esModule) return value;
/******/ 		var ns = Object.create(null);
/******/ 		__webpack_require__.r(ns);
/******/ 		Object.defineProperty(ns, 'default', { enumerable: true, value: value });
/******/ 		if(mode & 2 && typeof value != 'string') for(var key in value) __webpack_require__.d(ns, key, function(key) { return value[key]; }.bind(null, key));
/******/ 		return ns;
/******/ 	};
/******/
/******/ 	// getDefaultExport function for compatibility with non-harmony modules
/******/ 	__webpack_require__.n = function(module) {
/******/ 		var getter = module && module.__esModule ?
/******/ 			function getDefault() { return module['default']; } :
/******/ 			function getModuleExports() { return module; };
/******/ 		__webpack_require__.d(getter, 'a', getter);
/******/ 		return getter;
/******/ 	};
/******/
/******/ 	// Object.prototype.hasOwnProperty.call
/******/ 	__webpack_require__.o = function(object, property) { return Object.prototype.hasOwnProperty.call(object, property); };
/******/
/******/ 	// __webpack_public_path__
/******/ 	__webpack_require__.p = "/js/";
/******/
/******/
/******/ 	// Load entry module and return exports
/******/ 	return __webpack_require__(__webpack_require__.s = 0);
/******/ })
/************************************************************************/
/******/ ({

/***/ "../deps/phoenix/priv/static/phoenix.js":
/*!**********************************************!*\
  !*** ../deps/phoenix/priv/static/phoenix.js ***!
  \**********************************************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

!function (e, t) {
   true ? module.exports = t() : undefined;
}(this, function () {
  return function (e) {
    var t = {};

    function n(i) {
      if (t[i]) return t[i].exports;
      var o = t[i] = {
        i: i,
        l: !1,
        exports: {}
      };
      return e[i].call(o.exports, o, o.exports, n), o.l = !0, o.exports;
    }

    return n.m = e, n.c = t, n.d = function (e, t, i) {
      n.o(e, t) || Object.defineProperty(e, t, {
        enumerable: !0,
        get: i
      });
    }, n.r = function (e) {
      "undefined" != typeof Symbol && Symbol.toStringTag && Object.defineProperty(e, Symbol.toStringTag, {
        value: "Module"
      }), Object.defineProperty(e, "__esModule", {
        value: !0
      });
    }, n.t = function (e, t) {
      if (1 & t && (e = n(e)), 8 & t) return e;
      if (4 & t && "object" == typeof e && e && e.__esModule) return e;
      var i = Object.create(null);
      if (n.r(i), Object.defineProperty(i, "default", {
        enumerable: !0,
        value: e
      }), 2 & t && "string" != typeof e) for (var o in e) n.d(i, o, function (t) {
        return e[t];
      }.bind(null, o));
      return i;
    }, n.n = function (e) {
      var t = e && e.__esModule ? function () {
        return e.default;
      } : function () {
        return e;
      };
      return n.d(t, "a", t), t;
    }, n.o = function (e, t) {
      return Object.prototype.hasOwnProperty.call(e, t);
    }, n.p = "", n(n.s = 0);
  }([function (e, t, n) {
    (function (t) {
      e.exports = t.Phoenix = n(2);
    }).call(this, n(1));
  }, function (e, t) {
    var n;

    n = function () {
      return this;
    }();

    try {
      n = n || new Function("return this")();
    } catch (e) {
      "object" == typeof window && (n = window);
    }

    e.exports = n;
  }, function (e, t, n) {
    "use strict";

    function i(e) {
      return function (e) {
        if (Array.isArray(e)) return a(e);
      }(e) || function (e) {
        if ("undefined" != typeof Symbol && Symbol.iterator in Object(e)) return Array.from(e);
      }(e) || s(e) || function () {
        throw new TypeError("Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
      }();
    }

    function o(e) {
      return (o = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (e) {
        return typeof e;
      } : function (e) {
        return e && "function" == typeof Symbol && e.constructor === Symbol && e !== Symbol.prototype ? "symbol" : typeof e;
      })(e);
    }

    function r(e, t) {
      return function (e) {
        if (Array.isArray(e)) return e;
      }(e) || function (e, t) {
        if ("undefined" == typeof Symbol || !(Symbol.iterator in Object(e))) return;
        var n = [],
            i = !0,
            o = !1,
            r = void 0;

        try {
          for (var s, a = e[Symbol.iterator](); !(i = (s = a.next()).done) && (n.push(s.value), !t || n.length !== t); i = !0);
        } catch (e) {
          o = !0, r = e;
        } finally {
          try {
            i || null == a.return || a.return();
          } finally {
            if (o) throw r;
          }
        }

        return n;
      }(e, t) || s(e, t) || function () {
        throw new TypeError("Invalid attempt to destructure non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
      }();
    }

    function s(e, t) {
      if (e) {
        if ("string" == typeof e) return a(e, t);
        var n = Object.prototype.toString.call(e).slice(8, -1);
        return "Object" === n && e.constructor && (n = e.constructor.name), "Map" === n || "Set" === n ? Array.from(n) : "Arguments" === n || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n) ? a(e, t) : void 0;
      }
    }

    function a(e, t) {
      (null == t || t > e.length) && (t = e.length);

      for (var n = 0, i = new Array(t); n < t; n++) i[n] = e[n];

      return i;
    }

    function c(e, t) {
      if (!(e instanceof t)) throw new TypeError("Cannot call a class as a function");
    }

    function u(e, t) {
      for (var n = 0; n < t.length; n++) {
        var i = t[n];
        i.enumerable = i.enumerable || !1, i.configurable = !0, "value" in i && (i.writable = !0), Object.defineProperty(e, i.key, i);
      }
    }

    function h(e, t, n) {
      return t && u(e.prototype, t), n && u(e, n), e;
    }

    n.r(t), n.d(t, "Channel", function () {
      return O;
    }), n.d(t, "Serializer", function () {
      return _;
    }), n.d(t, "Socket", function () {
      return H;
    }), n.d(t, "LongPoll", function () {
      return U;
    }), n.d(t, "Ajax", function () {
      return D;
    }), n.d(t, "Presence", function () {
      return M;
    });

    var l = "undefined" != typeof self ? self : null,
        f = "undefined" != typeof window ? window : null,
        d = l || f || void 0,
        p = 0,
        v = 1,
        y = 2,
        m = 3,
        g = "closed",
        k = "errored",
        b = "joined",
        j = "joining",
        T = "leaving",
        C = "phx_close",
        R = "phx_error",
        E = "phx_join",
        w = "phx_reply",
        S = "phx_leave",
        A = "longpoll",
        L = "websocket",
        x = function (e) {
      if ("function" == typeof e) return e;
      return function () {
        return e;
      };
    },
        P = function () {
      function e(t, n, i, o) {
        c(this, e), this.channel = t, this.event = n, this.payload = i || function () {
          return {};
        }, this.receivedResp = null, this.timeout = o, this.timeoutTimer = null, this.recHooks = [], this.sent = !1;
      }

      return h(e, [{
        key: "resend",
        value: function (e) {
          this.timeout = e, this.reset(), this.send();
        }
      }, {
        key: "send",
        value: function () {
          this.hasReceived("timeout") || (this.startTimeout(), this.sent = !0, this.channel.socket.push({
            topic: this.channel.topic,
            event: this.event,
            payload: this.payload(),
            ref: this.ref,
            join_ref: this.channel.joinRef()
          }));
        }
      }, {
        key: "receive",
        value: function (e, t) {
          return this.hasReceived(e) && t(this.receivedResp.response), this.recHooks.push({
            status: e,
            callback: t
          }), this;
        }
      }, {
        key: "reset",
        value: function () {
          this.cancelRefEvent(), this.ref = null, this.refEvent = null, this.receivedResp = null, this.sent = !1;
        }
      }, {
        key: "matchReceive",
        value: function (e) {
          var t = e.status,
              n = e.response;
          e.ref;
          this.recHooks.filter(function (e) {
            return e.status === t;
          }).forEach(function (e) {
            return e.callback(n);
          });
        }
      }, {
        key: "cancelRefEvent",
        value: function () {
          this.refEvent && this.channel.off(this.refEvent);
        }
      }, {
        key: "cancelTimeout",
        value: function () {
          clearTimeout(this.timeoutTimer), this.timeoutTimer = null;
        }
      }, {
        key: "startTimeout",
        value: function () {
          var e = this;
          this.timeoutTimer && this.cancelTimeout(), this.ref = this.channel.socket.makeRef(), this.refEvent = this.channel.replyEventName(this.ref), this.channel.on(this.refEvent, function (t) {
            e.cancelRefEvent(), e.cancelTimeout(), e.receivedResp = t, e.matchReceive(t);
          }), this.timeoutTimer = setTimeout(function () {
            e.trigger("timeout", {});
          }, this.timeout);
        }
      }, {
        key: "hasReceived",
        value: function (e) {
          return this.receivedResp && this.receivedResp.status === e;
        }
      }, {
        key: "trigger",
        value: function (e, t) {
          this.channel.trigger(this.refEvent, {
            status: e,
            response: t
          });
        }
      }]), e;
    }(),
        O = function () {
      function e(t, n, i) {
        var o = this;
        c(this, e), this.state = g, this.topic = t, this.params = x(n || {}), this.socket = i, this.bindings = [], this.bindingRef = 0, this.timeout = this.socket.timeout, this.joinedOnce = !1, this.joinPush = new P(this, E, this.params, this.timeout), this.pushBuffer = [], this.stateChangeRefs = [], this.rejoinTimer = new N(function () {
          o.socket.isConnected() && o.rejoin();
        }, this.socket.rejoinAfterMs), this.stateChangeRefs.push(this.socket.onError(function () {
          return o.rejoinTimer.reset();
        })), this.stateChangeRefs.push(this.socket.onOpen(function () {
          o.rejoinTimer.reset(), o.isErrored() && o.rejoin();
        })), this.joinPush.receive("ok", function () {
          o.state = b, o.rejoinTimer.reset(), o.pushBuffer.forEach(function (e) {
            return e.send();
          }), o.pushBuffer = [];
        }), this.joinPush.receive("error", function () {
          o.state = k, o.socket.isConnected() && o.rejoinTimer.scheduleTimeout();
        }), this.onClose(function () {
          o.rejoinTimer.reset(), o.socket.hasLogger() && o.socket.log("channel", "close ".concat(o.topic, " ").concat(o.joinRef())), o.state = g, o.socket.remove(o);
        }), this.onError(function (e) {
          o.socket.hasLogger() && o.socket.log("channel", "error ".concat(o.topic), e), o.isJoining() && o.joinPush.reset(), o.state = k, o.socket.isConnected() && o.rejoinTimer.scheduleTimeout();
        }), this.joinPush.receive("timeout", function () {
          o.socket.hasLogger() && o.socket.log("channel", "timeout ".concat(o.topic, " (").concat(o.joinRef(), ")"), o.joinPush.timeout), new P(o, S, x({}), o.timeout).send(), o.state = k, o.joinPush.reset(), o.socket.isConnected() && o.rejoinTimer.scheduleTimeout();
        }), this.on(w, function (e, t) {
          o.trigger(o.replyEventName(t), e);
        });
      }

      return h(e, [{
        key: "join",
        value: function () {
          var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : this.timeout;
          if (this.joinedOnce) throw new Error("tried to join multiple times. 'join' can only be called a single time per channel instance");
          return this.timeout = e, this.joinedOnce = !0, this.rejoin(), this.joinPush;
        }
      }, {
        key: "onClose",
        value: function (e) {
          this.on(C, e);
        }
      }, {
        key: "onError",
        value: function (e) {
          return this.on(R, function (t) {
            return e(t);
          });
        }
      }, {
        key: "on",
        value: function (e, t) {
          var n = this.bindingRef++;
          return this.bindings.push({
            event: e,
            ref: n,
            callback: t
          }), n;
        }
      }, {
        key: "off",
        value: function (e, t) {
          this.bindings = this.bindings.filter(function (n) {
            return !(n.event === e && (void 0 === t || t === n.ref));
          });
        }
      }, {
        key: "canPush",
        value: function () {
          return this.socket.isConnected() && this.isJoined();
        }
      }, {
        key: "push",
        value: function (e, t) {
          var n = arguments.length > 2 && void 0 !== arguments[2] ? arguments[2] : this.timeout;
          if (t = t || {}, !this.joinedOnce) throw new Error("tried to push '".concat(e, "' to '").concat(this.topic, "' before joining. Use channel.join() before pushing events"));
          var i = new P(this, e, function () {
            return t;
          }, n);
          return this.canPush() ? i.send() : (i.startTimeout(), this.pushBuffer.push(i)), i;
        }
      }, {
        key: "leave",
        value: function () {
          var e = this,
              t = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : this.timeout;
          this.rejoinTimer.reset(), this.joinPush.cancelTimeout(), this.state = T;

          var n = function () {
            e.socket.hasLogger() && e.socket.log("channel", "leave ".concat(e.topic)), e.trigger(C, "leave");
          },
              i = new P(this, S, x({}), t);

          return i.receive("ok", function () {
            return n();
          }).receive("timeout", function () {
            return n();
          }), i.send(), this.canPush() || i.trigger("ok", {}), i;
        }
      }, {
        key: "onMessage",
        value: function (e, t, n) {
          return t;
        }
      }, {
        key: "isMember",
        value: function (e, t, n, i) {
          return this.topic === e && (!i || i === this.joinRef() || (this.socket.hasLogger() && this.socket.log("channel", "dropping outdated message", {
            topic: e,
            event: t,
            payload: n,
            joinRef: i
          }), !1));
        }
      }, {
        key: "joinRef",
        value: function () {
          return this.joinPush.ref;
        }
      }, {
        key: "rejoin",
        value: function () {
          var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : this.timeout;
          this.isLeaving() || (this.socket.leaveOpenTopic(this.topic), this.state = j, this.joinPush.resend(e));
        }
      }, {
        key: "trigger",
        value: function (e, t, n, i) {
          var o = this.onMessage(e, t, n, i);
          if (t && !o) throw new Error("channel onMessage callbacks must return the payload, modified or unmodified");

          for (var r = this.bindings.filter(function (t) {
            return t.event === e;
          }), s = 0; s < r.length; s++) {
            r[s].callback(o, n, i || this.joinRef());
          }
        }
      }, {
        key: "replyEventName",
        value: function (e) {
          return "chan_reply_".concat(e);
        }
      }, {
        key: "isClosed",
        value: function () {
          return this.state === g;
        }
      }, {
        key: "isErrored",
        value: function () {
          return this.state === k;
        }
      }, {
        key: "isJoined",
        value: function () {
          return this.state === b;
        }
      }, {
        key: "isJoining",
        value: function () {
          return this.state === j;
        }
      }, {
        key: "isLeaving",
        value: function () {
          return this.state === T;
        }
      }]), e;
    }(),
        _ = {
      HEADER_LENGTH: 1,
      META_LENGTH: 4,
      KINDS: {
        push: 0,
        reply: 1,
        broadcast: 2
      },
      encode: function (e, t) {
        if (e.payload.constructor === ArrayBuffer) return t(this.binaryEncode(e));
        var n = [e.join_ref, e.ref, e.topic, e.event, e.payload];
        return t(JSON.stringify(n));
      },
      decode: function (e, t) {
        if (e.constructor === ArrayBuffer) return t(this.binaryDecode(e));
        var n = r(JSON.parse(e), 5);
        return t({
          join_ref: n[0],
          ref: n[1],
          topic: n[2],
          event: n[3],
          payload: n[4]
        });
      },
      binaryEncode: function (e) {
        var t = e.join_ref,
            n = e.ref,
            i = e.event,
            o = e.topic,
            r = e.payload,
            s = this.META_LENGTH + t.length + n.length + o.length + i.length,
            a = new ArrayBuffer(this.HEADER_LENGTH + s),
            c = new DataView(a),
            u = 0;
        c.setUint8(u++, this.KINDS.push), c.setUint8(u++, t.length), c.setUint8(u++, n.length), c.setUint8(u++, o.length), c.setUint8(u++, i.length), Array.from(t, function (e) {
          return c.setUint8(u++, e.charCodeAt(0));
        }), Array.from(n, function (e) {
          return c.setUint8(u++, e.charCodeAt(0));
        }), Array.from(o, function (e) {
          return c.setUint8(u++, e.charCodeAt(0));
        }), Array.from(i, function (e) {
          return c.setUint8(u++, e.charCodeAt(0));
        });
        var h = new Uint8Array(a.byteLength + r.byteLength);
        return h.set(new Uint8Array(a), 0), h.set(new Uint8Array(r), a.byteLength), h.buffer;
      },
      binaryDecode: function (e) {
        var t = new DataView(e),
            n = t.getUint8(0),
            i = new TextDecoder();

        switch (n) {
          case this.KINDS.push:
            return this.decodePush(e, t, i);

          case this.KINDS.reply:
            return this.decodeReply(e, t, i);

          case this.KINDS.broadcast:
            return this.decodeBroadcast(e, t, i);
        }
      },
      decodePush: function (e, t, n) {
        var i = t.getUint8(1),
            o = t.getUint8(2),
            r = t.getUint8(3),
            s = this.HEADER_LENGTH + this.META_LENGTH - 1,
            a = n.decode(e.slice(s, s + i));
        s += i;
        var c = n.decode(e.slice(s, s + o));
        s += o;
        var u = n.decode(e.slice(s, s + r));
        return s += r, {
          join_ref: a,
          ref: null,
          topic: c,
          event: u,
          payload: e.slice(s, e.byteLength)
        };
      },
      decodeReply: function (e, t, n) {
        var i = t.getUint8(1),
            o = t.getUint8(2),
            r = t.getUint8(3),
            s = t.getUint8(4),
            a = this.HEADER_LENGTH + this.META_LENGTH,
            c = n.decode(e.slice(a, a + i));
        a += i;
        var u = n.decode(e.slice(a, a + o));
        a += o;
        var h = n.decode(e.slice(a, a + r));
        a += r;
        var l = n.decode(e.slice(a, a + s));
        a += s;
        var f = e.slice(a, e.byteLength);
        return {
          join_ref: c,
          ref: u,
          topic: h,
          event: w,
          payload: {
            status: l,
            response: f
          }
        };
      },
      decodeBroadcast: function (e, t, n) {
        var i = t.getUint8(1),
            o = t.getUint8(2),
            r = this.HEADER_LENGTH + 2,
            s = n.decode(e.slice(r, r + i));
        r += i;
        var a = n.decode(e.slice(r, r + o));
        return r += o, {
          join_ref: null,
          ref: null,
          topic: s,
          event: a,
          payload: e.slice(r, e.byteLength)
        };
      }
    },
        H = function () {
      function e(t) {
        var n = this,
            i = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : {};
        c(this, e), this.stateChangeCallbacks = {
          open: [],
          close: [],
          error: [],
          message: []
        }, this.channels = [], this.sendBuffer = [], this.ref = 0, this.timeout = i.timeout || 1e4, this.transport = i.transport || d.WebSocket || U, this.defaultEncoder = _.encode.bind(_), this.defaultDecoder = _.decode.bind(_), this.closeWasClean = !1, this.unloaded = !1, this.binaryType = i.binaryType || "arraybuffer", this.transport !== U ? (this.encode = i.encode || this.defaultEncoder, this.decode = i.decode || this.defaultDecoder) : (this.encode = this.defaultEncoder, this.decode = this.defaultDecoder), f && f.addEventListener && f.addEventListener("beforeunload", function (e) {
          n.conn && (n.unloaded = !0, n.abnormalClose("unloaded"));
        }), this.heartbeatIntervalMs = i.heartbeatIntervalMs || 3e4, this.rejoinAfterMs = function (e) {
          return i.rejoinAfterMs ? i.rejoinAfterMs(e) : [1e3, 2e3, 5e3][e - 1] || 1e4;
        }, this.reconnectAfterMs = function (e) {
          return n.unloaded ? 100 : i.reconnectAfterMs ? i.reconnectAfterMs(e) : [10, 50, 100, 150, 200, 250, 500, 1e3, 2e3][e - 1] || 5e3;
        }, this.logger = i.logger || null, this.longpollerTimeout = i.longpollerTimeout || 2e4, this.params = x(i.params || {}), this.endPoint = "".concat(t, "/").concat(L), this.vsn = i.vsn || "2.0.0", this.heartbeatTimer = null, this.pendingHeartbeatRef = null, this.reconnectTimer = new N(function () {
          n.teardown(function () {
            return n.connect();
          });
        }, this.reconnectAfterMs);
      }

      return h(e, [{
        key: "protocol",
        value: function () {
          return location.protocol.match(/^https/) ? "wss" : "ws";
        }
      }, {
        key: "endPointURL",
        value: function () {
          var e = D.appendParams(D.appendParams(this.endPoint, this.params()), {
            vsn: this.vsn
          });
          return "/" !== e.charAt(0) ? e : "/" === e.charAt(1) ? "".concat(this.protocol(), ":").concat(e) : "".concat(this.protocol(), "://").concat(location.host).concat(e);
        }
      }, {
        key: "disconnect",
        value: function (e, t, n) {
          this.closeWasClean = !0, this.reconnectTimer.reset(), this.teardown(e, t, n);
        }
      }, {
        key: "connect",
        value: function (e) {
          var t = this;
          e && (console && console.log("passing params to connect is deprecated. Instead pass :params to the Socket constructor"), this.params = x(e)), this.conn || (this.closeWasClean = !1, this.conn = new this.transport(this.endPointURL()), this.conn.binaryType = this.binaryType, this.conn.timeout = this.longpollerTimeout, this.conn.onopen = function () {
            return t.onConnOpen();
          }, this.conn.onerror = function (e) {
            return t.onConnError(e);
          }, this.conn.onmessage = function (e) {
            return t.onConnMessage(e);
          }, this.conn.onclose = function (e) {
            return t.onConnClose(e);
          });
        }
      }, {
        key: "log",
        value: function (e, t, n) {
          this.logger(e, t, n);
        }
      }, {
        key: "hasLogger",
        value: function () {
          return null !== this.logger;
        }
      }, {
        key: "onOpen",
        value: function (e) {
          var t = this.makeRef();
          return this.stateChangeCallbacks.open.push([t, e]), t;
        }
      }, {
        key: "onClose",
        value: function (e) {
          var t = this.makeRef();
          return this.stateChangeCallbacks.close.push([t, e]), t;
        }
      }, {
        key: "onError",
        value: function (e) {
          var t = this.makeRef();
          return this.stateChangeCallbacks.error.push([t, e]), t;
        }
      }, {
        key: "onMessage",
        value: function (e) {
          var t = this.makeRef();
          return this.stateChangeCallbacks.message.push([t, e]), t;
        }
      }, {
        key: "onConnOpen",
        value: function () {
          this.hasLogger() && this.log("transport", "connected to ".concat(this.endPointURL())), this.unloaded = !1, this.closeWasClean = !1, this.flushSendBuffer(), this.reconnectTimer.reset(), this.resetHeartbeat(), this.stateChangeCallbacks.open.forEach(function (e) {
            return (0, r(e, 2)[1])();
          });
        }
      }, {
        key: "heartbeatTimeout",
        value: function () {
          this.pendingHeartbeatRef && (this.pendingHeartbeatRef = null, this.hasLogger() && this.log("transport", "heartbeat timeout. Attempting to re-establish connection"), this.abnormalClose("heartbeat timeout"));
        }
      }, {
        key: "resetHeartbeat",
        value: function () {
          var e = this;
          this.conn && this.conn.skipHeartbeat || (this.pendingHeartbeatRef = null, clearTimeout(this.heartbeatTimer), setTimeout(function () {
            return e.sendHeartbeat();
          }, this.heartbeatIntervalMs));
        }
      }, {
        key: "teardown",
        value: function (e, t, n) {
          var i = this;
          if (!this.conn) return e && e();
          this.waitForBufferDone(function () {
            i.conn && (t ? i.conn.close(t, n || "") : i.conn.close()), i.waitForSocketClosed(function () {
              i.conn && (i.conn.onclose = function () {}, i.conn = null), e && e();
            });
          });
        }
      }, {
        key: "waitForBufferDone",
        value: function (e) {
          var t = this,
              n = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : 1;
          5 !== n && this.conn && this.conn.bufferedAmount ? setTimeout(function () {
            t.waitForBufferDone(e, n + 1);
          }, 150 * n) : e();
        }
      }, {
        key: "waitForSocketClosed",
        value: function (e) {
          var t = this,
              n = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : 1;
          5 !== n && this.conn && this.conn.readyState !== m ? setTimeout(function () {
            t.waitForSocketClosed(e, n + 1);
          }, 150 * n) : e();
        }
      }, {
        key: "onConnClose",
        value: function (e) {
          this.hasLogger() && this.log("transport", "close", e), this.triggerChanError(), clearTimeout(this.heartbeatTimer), this.closeWasClean || this.reconnectTimer.scheduleTimeout(), this.stateChangeCallbacks.close.forEach(function (t) {
            return (0, r(t, 2)[1])(e);
          });
        }
      }, {
        key: "onConnError",
        value: function (e) {
          this.hasLogger() && this.log("transport", e), this.triggerChanError(), this.stateChangeCallbacks.error.forEach(function (t) {
            return (0, r(t, 2)[1])(e);
          });
        }
      }, {
        key: "triggerChanError",
        value: function () {
          this.channels.forEach(function (e) {
            e.isErrored() || e.isLeaving() || e.isClosed() || e.trigger(R);
          });
        }
      }, {
        key: "connectionState",
        value: function () {
          switch (this.conn && this.conn.readyState) {
            case p:
              return "connecting";

            case v:
              return "open";

            case y:
              return "closing";

            default:
              return "closed";
          }
        }
      }, {
        key: "isConnected",
        value: function () {
          return "open" === this.connectionState();
        }
      }, {
        key: "remove",
        value: function (e) {
          this.off(e.stateChangeRefs), this.channels = this.channels.filter(function (t) {
            return t.joinRef() !== e.joinRef();
          });
        }
      }, {
        key: "off",
        value: function (e) {
          for (var t in this.stateChangeCallbacks) this.stateChangeCallbacks[t] = this.stateChangeCallbacks[t].filter(function (t) {
            var n = r(t, 1)[0];
            return -1 === e.indexOf(n);
          });
        }
      }, {
        key: "channel",
        value: function (e) {
          var t = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : {},
              n = new O(e, t, this);
          return this.channels.push(n), n;
        }
      }, {
        key: "push",
        value: function (e) {
          var t = this;

          if (this.hasLogger()) {
            var n = e.topic,
                i = e.event,
                o = e.payload,
                r = e.ref,
                s = e.join_ref;
            this.log("push", "".concat(n, " ").concat(i, " (").concat(s, ", ").concat(r, ")"), o);
          }

          this.isConnected() ? this.encode(e, function (e) {
            return t.conn.send(e);
          }) : this.sendBuffer.push(function () {
            return t.encode(e, function (e) {
              return t.conn.send(e);
            });
          });
        }
      }, {
        key: "makeRef",
        value: function () {
          var e = this.ref + 1;
          return e === this.ref ? this.ref = 0 : this.ref = e, this.ref.toString();
        }
      }, {
        key: "sendHeartbeat",
        value: function () {
          var e = this;
          this.pendingHeartbeatRef && !this.isConnected() || (this.pendingHeartbeatRef = this.makeRef(), this.push({
            topic: "phoenix",
            event: "heartbeat",
            payload: {},
            ref: this.pendingHeartbeatRef
          }), this.heartbeatTimer = setTimeout(function () {
            return e.heartbeatTimeout();
          }, this.heartbeatIntervalMs));
        }
      }, {
        key: "abnormalClose",
        value: function (e) {
          this.closeWasClean = !1, this.isConnected() && this.conn.close(1e3, e);
        }
      }, {
        key: "flushSendBuffer",
        value: function () {
          this.isConnected() && this.sendBuffer.length > 0 && (this.sendBuffer.forEach(function (e) {
            return e();
          }), this.sendBuffer = []);
        }
      }, {
        key: "onConnMessage",
        value: function (e) {
          var t = this;
          this.decode(e.data, function (e) {
            var n = e.topic,
                i = e.event,
                o = e.payload,
                s = e.ref,
                a = e.join_ref;
            s && s === t.pendingHeartbeatRef && (clearTimeout(t.heartbeatTimer), t.pendingHeartbeatRef = null, setTimeout(function () {
              return t.sendHeartbeat();
            }, t.heartbeatIntervalMs)), t.hasLogger() && t.log("receive", "".concat(o.status || "", " ").concat(n, " ").concat(i, " ").concat(s && "(" + s + ")" || ""), o);

            for (var c = 0; c < t.channels.length; c++) {
              var u = t.channels[c];
              u.isMember(n, i, o, a) && u.trigger(i, o, s, a);
            }

            for (var h = 0; h < t.stateChangeCallbacks.message.length; h++) {
              (0, r(t.stateChangeCallbacks.message[h], 2)[1])(e);
            }
          });
        }
      }, {
        key: "leaveOpenTopic",
        value: function (e) {
          var t = this.channels.find(function (t) {
            return t.topic === e && (t.isJoined() || t.isJoining());
          });
          t && (this.hasLogger() && this.log("transport", 'leaving duplicate topic "'.concat(e, '"')), t.leave());
        }
      }]), e;
    }(),
        U = function () {
      function e(t) {
        c(this, e), this.endPoint = null, this.token = null, this.skipHeartbeat = !0, this.onopen = function () {}, this.onerror = function () {}, this.onmessage = function () {}, this.onclose = function () {}, this.pollEndpoint = this.normalizeEndpoint(t), this.readyState = p, this.poll();
      }

      return h(e, [{
        key: "normalizeEndpoint",
        value: function (e) {
          return e.replace("ws://", "http://").replace("wss://", "https://").replace(new RegExp("(.*)/" + L), "$1/" + A);
        }
      }, {
        key: "endpointURL",
        value: function () {
          return D.appendParams(this.pollEndpoint, {
            token: this.token
          });
        }
      }, {
        key: "closeAndRetry",
        value: function () {
          this.close(), this.readyState = p;
        }
      }, {
        key: "ontimeout",
        value: function () {
          this.onerror("timeout"), this.closeAndRetry();
        }
      }, {
        key: "poll",
        value: function () {
          var e = this;
          this.readyState !== v && this.readyState !== p || D.request("GET", this.endpointURL(), "application/json", null, this.timeout, this.ontimeout.bind(this), function (t) {
            if (t) {
              var n = t.status,
                  i = t.token,
                  o = t.messages;
              e.token = i;
            } else n = 0;

            switch (n) {
              case 200:
                o.forEach(function (t) {
                  setTimeout(function () {
                    e.onmessage({
                      data: t
                    });
                  }, 0);
                }), e.poll();
                break;

              case 204:
                e.poll();
                break;

              case 410:
                e.readyState = v, e.onopen(), e.poll();
                break;

              case 403:
                e.onerror(), e.close();
                break;

              case 0:
              case 500:
                e.onerror(), e.closeAndRetry();
                break;

              default:
                throw new Error("unhandled poll status ".concat(n));
            }
          });
        }
      }, {
        key: "send",
        value: function (e) {
          var t = this;
          D.request("POST", this.endpointURL(), "application/json", e, this.timeout, this.onerror.bind(this, "timeout"), function (e) {
            e && 200 === e.status || (t.onerror(e && e.status), t.closeAndRetry());
          });
        }
      }, {
        key: "close",
        value: function (e, t) {
          this.readyState = m, this.onclose();
        }
      }]), e;
    }(),
        D = function () {
      function e() {
        c(this, e);
      }

      return h(e, null, [{
        key: "request",
        value: function (e, t, n, i, o, r, s) {
          if (d.XDomainRequest) {
            var a = new XDomainRequest();
            this.xdomainRequest(a, e, t, i, o, r, s);
          } else {
            var c = new d.XMLHttpRequest();
            this.xhrRequest(c, e, t, n, i, o, r, s);
          }
        }
      }, {
        key: "xdomainRequest",
        value: function (e, t, n, i, o, r, s) {
          var a = this;
          e.timeout = o, e.open(t, n), e.onload = function () {
            var t = a.parseJSON(e.responseText);
            s && s(t);
          }, r && (e.ontimeout = r), e.onprogress = function () {}, e.send(i);
        }
      }, {
        key: "xhrRequest",
        value: function (e, t, n, i, o, r, s, a) {
          var c = this;
          e.open(t, n, !0), e.timeout = r, e.setRequestHeader("Content-Type", i), e.onerror = function () {
            a && a(null);
          }, e.onreadystatechange = function () {
            if (e.readyState === c.states.complete && a) {
              var t = c.parseJSON(e.responseText);
              a(t);
            }
          }, s && (e.ontimeout = s), e.send(o);
        }
      }, {
        key: "parseJSON",
        value: function (e) {
          if (!e || "" === e) return null;

          try {
            return JSON.parse(e);
          } catch (t) {
            return console && console.log("failed to parse JSON response", e), null;
          }
        }
      }, {
        key: "serialize",
        value: function (e, t) {
          var n = [];

          for (var i in e) if (e.hasOwnProperty(i)) {
            var r = t ? "".concat(t, "[").concat(i, "]") : i,
                s = e[i];
            "object" === o(s) ? n.push(this.serialize(s, r)) : n.push(encodeURIComponent(r) + "=" + encodeURIComponent(s));
          }

          return n.join("&");
        }
      }, {
        key: "appendParams",
        value: function (e, t) {
          if (0 === Object.keys(t).length) return e;
          var n = e.match(/\?/) ? "&" : "?";
          return "".concat(e).concat(n).concat(this.serialize(t));
        }
      }]), e;
    }();

    D.states = {
      complete: 4
    };

    var M = function () {
      function e(t) {
        var n = this,
            i = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : {};
        c(this, e);
        var o = i.events || {
          state: "presence_state",
          diff: "presence_diff"
        };
        this.state = {}, this.pendingDiffs = [], this.channel = t, this.joinRef = null, this.caller = {
          onJoin: function () {},
          onLeave: function () {},
          onSync: function () {}
        }, this.channel.on(o.state, function (t) {
          var i = n.caller,
              o = i.onJoin,
              r = i.onLeave,
              s = i.onSync;
          n.joinRef = n.channel.joinRef(), n.state = e.syncState(n.state, t, o, r), n.pendingDiffs.forEach(function (t) {
            n.state = e.syncDiff(n.state, t, o, r);
          }), n.pendingDiffs = [], s();
        }), this.channel.on(o.diff, function (t) {
          var i = n.caller,
              o = i.onJoin,
              r = i.onLeave,
              s = i.onSync;
          n.inPendingSyncState() ? n.pendingDiffs.push(t) : (n.state = e.syncDiff(n.state, t, o, r), s());
        });
      }

      return h(e, [{
        key: "onJoin",
        value: function (e) {
          this.caller.onJoin = e;
        }
      }, {
        key: "onLeave",
        value: function (e) {
          this.caller.onLeave = e;
        }
      }, {
        key: "onSync",
        value: function (e) {
          this.caller.onSync = e;
        }
      }, {
        key: "list",
        value: function (t) {
          return e.list(this.state, t);
        }
      }, {
        key: "inPendingSyncState",
        value: function () {
          return !this.joinRef || this.joinRef !== this.channel.joinRef();
        }
      }], [{
        key: "syncState",
        value: function (e, t, n, i) {
          var o = this,
              r = this.clone(e),
              s = {},
              a = {};
          return this.map(r, function (e, n) {
            t[e] || (a[e] = n);
          }), this.map(t, function (e, t) {
            var n = r[e];

            if (n) {
              var i = t.metas.map(function (e) {
                return e.phx_ref;
              }),
                  c = n.metas.map(function (e) {
                return e.phx_ref;
              }),
                  u = t.metas.filter(function (e) {
                return c.indexOf(e.phx_ref) < 0;
              }),
                  h = n.metas.filter(function (e) {
                return i.indexOf(e.phx_ref) < 0;
              });
              u.length > 0 && (s[e] = t, s[e].metas = u), h.length > 0 && (a[e] = o.clone(n), a[e].metas = h);
            } else s[e] = t;
          }), this.syncDiff(r, {
            joins: s,
            leaves: a
          }, n, i);
        }
      }, {
        key: "syncDiff",
        value: function (e, t, n, o) {
          var r = t.joins,
              s = t.leaves,
              a = this.clone(e);
          return n || (n = function () {}), o || (o = function () {}), this.map(r, function (e, t) {
            var o = a[e];

            if (a[e] = t, o) {
              var r,
                  s = a[e].metas.map(function (e) {
                return e.phx_ref;
              }),
                  c = o.metas.filter(function (e) {
                return s.indexOf(e.phx_ref) < 0;
              });
              (r = a[e].metas).unshift.apply(r, i(c));
            }

            n(e, o, t);
          }), this.map(s, function (e, t) {
            var n = a[e];

            if (n) {
              var i = t.metas.map(function (e) {
                return e.phx_ref;
              });
              n.metas = n.metas.filter(function (e) {
                return i.indexOf(e.phx_ref) < 0;
              }), o(e, n, t), 0 === n.metas.length && delete a[e];
            }
          }), a;
        }
      }, {
        key: "list",
        value: function (e, t) {
          return t || (t = function (e, t) {
            return t;
          }), this.map(e, function (e, n) {
            return t(e, n);
          });
        }
      }, {
        key: "map",
        value: function (e, t) {
          return Object.getOwnPropertyNames(e).map(function (n) {
            return t(n, e[n]);
          });
        }
      }, {
        key: "clone",
        value: function (e) {
          return JSON.parse(JSON.stringify(e));
        }
      }]), e;
    }(),
        N = function () {
      function e(t, n) {
        c(this, e), this.callback = t, this.timerCalc = n, this.timer = null, this.tries = 0;
      }

      return h(e, [{
        key: "reset",
        value: function () {
          this.tries = 0, clearTimeout(this.timer);
        }
      }, {
        key: "scheduleTimeout",
        value: function () {
          var e = this;
          clearTimeout(this.timer), this.timer = setTimeout(function () {
            e.tries = e.tries + 1, e.callback();
          }, this.timerCalc(this.tries + 1));
        }
      }]), e;
    }();
  }]);
});

/***/ }),

/***/ "../deps/phoenix_html/priv/static/phoenix_html.js":
/*!********************************************************!*\
  !*** ../deps/phoenix_html/priv/static/phoenix_html.js ***!
  \********************************************************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

"use strict";


(function () {
  var PolyfillEvent = eventConstructor();

  function eventConstructor() {
    if (typeof window.CustomEvent === "function") return window.CustomEvent; // IE<=9 Support

    function CustomEvent(event, params) {
      params = params || {
        bubbles: false,
        cancelable: false,
        detail: undefined
      };
      var evt = document.createEvent('CustomEvent');
      evt.initCustomEvent(event, params.bubbles, params.cancelable, params.detail);
      return evt;
    }

    CustomEvent.prototype = window.Event.prototype;
    return CustomEvent;
  }

  function buildHiddenInput(name, value) {
    var input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    return input;
  }

  function handleClick(element, targetModifierKey) {
    var to = element.getAttribute("data-to"),
        method = buildHiddenInput("_method", element.getAttribute("data-method")),
        csrf = buildHiddenInput("_csrf_token", element.getAttribute("data-csrf")),
        form = document.createElement("form"),
        target = element.getAttribute("target");
    form.method = element.getAttribute("data-method") === "get" ? "get" : "post";
    form.action = to;
    form.style.display = "hidden";
    if (target) form.target = target;else if (targetModifierKey) form.target = "_blank";
    form.appendChild(csrf);
    form.appendChild(method);
    document.body.appendChild(form);
    form.submit();
  }

  window.addEventListener("click", function (e) {
    var element = e.target;

    while (element && element.getAttribute) {
      var phoenixLinkEvent = new PolyfillEvent('phoenix.link.click', {
        "bubbles": true,
        "cancelable": true
      });

      if (!element.dispatchEvent(phoenixLinkEvent)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return false;
      }

      if (element.getAttribute("data-method")) {
        handleClick(element, e.metaKey || e.shiftKey);
        e.preventDefault();
        return false;
      } else {
        element = element.parentNode;
      }
    }
  }, false);
  window.addEventListener('phoenix.link.click', function (e) {
    var message = e.target.getAttribute("data-confirm");

    if (message && !window.confirm(message)) {
      e.preventDefault();
    }
  }, false);
})();

/***/ }),

/***/ "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js":
/*!**********************************************************************!*\
  !*** ../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js ***!
  \**********************************************************************/
/*! exports provided: LiveSocket */
/***/ (function(module, __webpack_exports__, __webpack_require__) {

"use strict";
__webpack_require__.r(__webpack_exports__);
/* harmony export (binding) */ __webpack_require__.d(__webpack_exports__, "LiveSocket", function() { return LiveSocket; });
// js/phoenix_live_view/constants.js
var CONSECUTIVE_RELOADS = "consecutive-reloads";
var MAX_RELOADS = 10;
var RELOAD_JITTER = [1e3, 3e3];
var FAILSAFE_JITTER = 3e4;
var PHX_EVENT_CLASSES = ["phx-click-loading", "phx-change-loading", "phx-submit-loading", "phx-keydown-loading", "phx-keyup-loading", "phx-blur-loading", "phx-focus-loading"];
var PHX_COMPONENT = "data-phx-component";
var PHX_LIVE_LINK = "data-phx-link";
var PHX_TRACK_STATIC = "track-static";
var PHX_LINK_STATE = "data-phx-link-state";
var PHX_REF = "data-phx-ref";
var PHX_TRACK_UPLOADS = "track-uploads";
var PHX_UPLOAD_REF = "data-phx-upload-ref";
var PHX_PREFLIGHTED_REFS = "data-phx-preflighted-refs";
var PHX_DONE_REFS = "data-phx-done-refs";
var PHX_DROP_TARGET = "drop-target";
var PHX_ACTIVE_ENTRY_REFS = "data-phx-active-refs";
var PHX_LIVE_FILE_UPDATED = "phx:live-file:updated";
var PHX_SKIP = "data-phx-skip";
var PHX_REMOVE = "data-phx-remove";
var PHX_PAGE_LOADING = "page-loading";
var PHX_CONNECTED_CLASS = "phx-connected";
var PHX_DISCONNECTED_CLASS = "phx-disconnected";
var PHX_NO_FEEDBACK_CLASS = "phx-no-feedback";
var PHX_ERROR_CLASS = "phx-error";
var PHX_PARENT_ID = "data-phx-parent-id";
var PHX_MAIN = "data-phx-main";
var PHX_ROOT_ID = "data-phx-root-id";
var PHX_TRIGGER_ACTION = "trigger-action";
var PHX_FEEDBACK_FOR = "feedback-for";
var PHX_HAS_FOCUSED = "phx-has-focused";
var FOCUSABLE_INPUTS = ["text", "textarea", "number", "email", "password", "search", "tel", "url", "date", "time"];
var CHECKABLE_INPUTS = ["checkbox", "radio"];
var PHX_HAS_SUBMITTED = "phx-has-submitted";
var PHX_SESSION = "data-phx-session";
var PHX_VIEW_SELECTOR = `[${PHX_SESSION}]`;
var PHX_STATIC = "data-phx-static";
var PHX_READONLY = "data-phx-readonly";
var PHX_DISABLED = "data-phx-disabled";
var PHX_DISABLE_WITH = "disable-with";
var PHX_DISABLE_WITH_RESTORE = "data-phx-disable-with-restore";
var PHX_HOOK = "hook";
var PHX_DEBOUNCE = "debounce";
var PHX_THROTTLE = "throttle";
var PHX_UPDATE = "update";
var PHX_KEY = "key";
var PHX_PRIVATE = "phxPrivate";
var PHX_AUTO_RECOVER = "auto-recover";
var PHX_LV_DEBUG = "phx:live-socket:debug";
var PHX_LV_PROFILE = "phx:live-socket:profiling";
var PHX_LV_LATENCY_SIM = "phx:live-socket:latency-sim";
var PHX_PROGRESS = "progress";
var LOADER_TIMEOUT = 1;
var BEFORE_UNLOAD_LOADER_TIMEOUT = 200;
var BINDING_PREFIX = "phx-";
var PUSH_TIMEOUT = 3e4;
var DEBOUNCE_TRIGGER = "debounce-trigger";
var THROTTLED = "throttled";
var DEBOUNCE_PREV_KEY = "debounce-prev-key";
var DEFAULTS = {
  debounce: 300,
  throttle: 300
};
var DYNAMICS = "d";
var STATIC = "s";
var COMPONENTS = "c";
var EVENTS = "e";
var REPLY = "r";
var TITLE = "t"; // js/phoenix_live_view/entry_uploader.js

var EntryUploader = class {
  constructor(entry, chunkSize, liveSocket) {
    this.liveSocket = liveSocket;
    this.entry = entry;
    this.offset = 0;
    this.chunkSize = chunkSize;
    this.chunkTimer = null;
    this.uploadChannel = liveSocket.channel(`lvu:${entry.ref}`, {
      token: entry.metadata()
    });
  }

  error(reason) {
    clearTimeout(this.chunkTimer);
    this.uploadChannel.leave();
    this.entry.error(reason);
  }

  upload() {
    this.uploadChannel.onError(reason => this.error(reason));
    this.uploadChannel.join().receive("ok", _data => this.readNextChunk()).receive("error", reason => this.error(reason));
  }

  isDone() {
    return this.offset >= this.entry.file.size;
  }

  readNextChunk() {
    let reader = new window.FileReader();
    let blob = this.entry.file.slice(this.offset, this.chunkSize + this.offset);

    reader.onload = e => {
      if (e.target.error === null) {
        this.offset += e.target.result.byteLength;
        this.pushChunk(e.target.result);
      } else {
        return logError("Read error: " + e.target.error);
      }
    };

    reader.readAsArrayBuffer(blob);
  }

  pushChunk(chunk) {
    if (!this.uploadChannel.isJoined()) {
      return;
    }

    this.uploadChannel.push("chunk", chunk).receive("ok", () => {
      this.entry.progress(this.offset / this.entry.file.size * 100);

      if (!this.isDone()) {
        this.chunkTimer = setTimeout(() => this.readNextChunk(), this.liveSocket.getLatencySim() || 0);
      }
    });
  }

}; // js/phoenix_live_view/utils.js

var logError = (msg, obj) => console.error && console.error(msg, obj);

var isCid = cid => typeof cid === "number";

function detectDuplicateIds() {
  let ids = new Set();
  let elems = document.querySelectorAll("*[id]");

  for (let i = 0, len = elems.length; i < len; i++) {
    if (ids.has(elems[i].id)) {
      console.error(`Multiple IDs detected: ${elems[i].id}. Ensure unique element ids.`);
    } else {
      ids.add(elems[i].id);
    }
  }
}

var debug = (view, kind, msg, obj) => {
  if (view.liveSocket.isDebugEnabled()) {
    console.log(`${view.id} ${kind}: ${msg} - `, obj);
  }
};

var closure = val => typeof val === "function" ? val : function () {
  return val;
};

var clone = obj => {
  return JSON.parse(JSON.stringify(obj));
};

var closestPhxBinding = (el, binding, borderEl) => {
  do {
    if (el.matches(`[${binding}]`)) {
      return el;
    }

    el = el.parentElement || el.parentNode;
  } while (el !== null && el.nodeType === 1 && !(borderEl && borderEl.isSameNode(el) || el.matches(PHX_VIEW_SELECTOR)));

  return null;
};

var isObject = obj => {
  return obj !== null && typeof obj === "object" && !(obj instanceof Array);
};

var isEqualObj = (obj1, obj2) => JSON.stringify(obj1) === JSON.stringify(obj2);

var isEmpty = obj => {
  for (let x in obj) {
    return false;
  }

  return true;
};

var maybe = (el, callback) => el && callback(el);

var channelUploader = function (entries, onError, resp, liveSocket) {
  entries.forEach(entry => {
    let entryUploader = new EntryUploader(entry, resp.config.chunk_size, liveSocket);
    entryUploader.upload();
  });
}; // js/phoenix_live_view/browser.js


var Browser = {
  canPushState() {
    return typeof history.pushState !== "undefined";
  },

  dropLocal(localStorage, namespace, subkey) {
    return localStorage.removeItem(this.localKey(namespace, subkey));
  },

  updateLocal(localStorage, namespace, subkey, initial, func) {
    let current = this.getLocal(localStorage, namespace, subkey);
    let key = this.localKey(namespace, subkey);
    let newVal = current === null ? initial : func(current);
    localStorage.setItem(key, JSON.stringify(newVal));
    return newVal;
  },

  getLocal(localStorage, namespace, subkey) {
    return JSON.parse(localStorage.getItem(this.localKey(namespace, subkey)));
  },

  updateCurrentState(callback) {
    if (!this.canPushState()) {
      return;
    }

    history.replaceState(callback(history.state || {}), "", window.location.href);
  },

  pushState(kind, meta, to) {
    if (this.canPushState()) {
      if (to !== window.location.href) {
        if (meta.type == "redirect" && meta.scroll) {
          let currentState = history.state || {};
          currentState.scroll = meta.scroll;
          history.replaceState(currentState, "", window.location.href);
        }

        delete meta.scroll;
        history[kind + "State"](meta, "", to || null);
        let hashEl = this.getHashTargetEl(window.location.hash);

        if (hashEl) {
          hashEl.scrollIntoView();
        } else if (meta.type === "redirect") {
          window.scroll(0, 0);
        }
      }
    } else {
      this.redirect(to);
    }
  },

  setCookie(name, value) {
    document.cookie = `${name}=${value}`;
  },

  getCookie(name) {
    return document.cookie.replace(new RegExp(`(?:(?:^|.*;s*)${name}s*=s*([^;]*).*$)|^.*$`), "$1");
  },

  redirect(toURL, flash) {
    if (flash) {
      Browser.setCookie("__phoenix_flash__", flash + "; max-age=60000; path=/");
    }

    window.location = toURL;
  },

  localKey(namespace, subkey) {
    return `${namespace}-${subkey}`;
  },

  getHashTargetEl(maybeHash) {
    let hash = maybeHash.toString().substring(1);

    if (hash === "") {
      return;
    }

    return document.getElementById(hash) || document.querySelector(`a[name="${hash}"]`);
  }

};
var browser_default = Browser; // js/phoenix_live_view/dom.js

var DOM = {
  byId(id) {
    return document.getElementById(id) || logError(`no id found for ${id}`);
  },

  removeClass(el, className) {
    el.classList.remove(className);

    if (el.classList.length === 0) {
      el.removeAttribute("class");
    }
  },

  all(node, query, callback) {
    if (!node) {
      return [];
    }

    let array = Array.from(node.querySelectorAll(query));
    return callback ? array.forEach(callback) : array;
  },

  childNodeLength(html) {
    let template = document.createElement("template");
    template.innerHTML = html;
    return template.content.childElementCount;
  },

  isUploadInput(el) {
    return el.type === "file" && el.getAttribute(PHX_UPLOAD_REF) !== null;
  },

  findUploadInputs(node) {
    return this.all(node, `input[type="file"][${PHX_UPLOAD_REF}]`);
  },

  findComponentNodeList(node, cid) {
    return this.filterWithinSameLiveView(this.all(node, `[${PHX_COMPONENT}="${cid}"]`), node);
  },

  isPhxDestroyed(node) {
    return node.id && DOM.private(node, "destroyed") ? true : false;
  },

  markPhxChildDestroyed(el) {
    el.setAttribute(PHX_SESSION, "");
    this.putPrivate(el, "destroyed", true);
  },

  findPhxChildrenInFragment(html, parentId) {
    let template = document.createElement("template");
    template.innerHTML = html;
    return this.findPhxChildren(template.content, parentId);
  },

  isIgnored(el, phxUpdate) {
    return (el.getAttribute(phxUpdate) || el.getAttribute("data-phx-update")) === "ignore";
  },

  isPhxUpdate(el, phxUpdate, updateTypes) {
    return el.getAttribute && updateTypes.indexOf(el.getAttribute(phxUpdate)) >= 0;
  },

  findPhxChildren(el, parentId) {
    return this.all(el, `${PHX_VIEW_SELECTOR}[${PHX_PARENT_ID}="${parentId}"]`);
  },

  findParentCIDs(node, cids) {
    let initial = new Set(cids);
    return cids.reduce((acc, cid) => {
      let selector = `[${PHX_COMPONENT}="${cid}"] [${PHX_COMPONENT}]`;
      this.filterWithinSameLiveView(this.all(node, selector), node).map(el => parseInt(el.getAttribute(PHX_COMPONENT))).forEach(childCID => acc.delete(childCID));
      return acc;
    }, initial);
  },

  filterWithinSameLiveView(nodes, parent) {
    if (parent.querySelector(PHX_VIEW_SELECTOR)) {
      return nodes.filter(el => this.withinSameLiveView(el, parent));
    } else {
      return nodes;
    }
  },

  withinSameLiveView(node, parent) {
    while (node = node.parentNode) {
      if (node.isSameNode(parent)) {
        return true;
      }

      if (node.getAttribute(PHX_SESSION) !== null) {
        return false;
      }
    }
  },

  private(el, key) {
    return el[PHX_PRIVATE] && el[PHX_PRIVATE][key];
  },

  deletePrivate(el, key) {
    el[PHX_PRIVATE] && delete el[PHX_PRIVATE][key];
  },

  putPrivate(el, key, value) {
    if (!el[PHX_PRIVATE]) {
      el[PHX_PRIVATE] = {};
    }

    el[PHX_PRIVATE][key] = value;
  },

  copyPrivates(target, source) {
    if (source[PHX_PRIVATE]) {
      target[PHX_PRIVATE] = clone(source[PHX_PRIVATE]);
    }
  },

  putTitle(str) {
    let titleEl = document.querySelector("title");
    let {
      prefix,
      suffix
    } = titleEl.dataset;
    document.title = `${prefix || ""}${str}${suffix || ""}`;
  },

  debounce(el, event, phxDebounce, defaultDebounce, phxThrottle, defaultThrottle, callback) {
    let debounce = el.getAttribute(phxDebounce);
    let throttle = el.getAttribute(phxThrottle);

    if (debounce === "") {
      debounce = defaultDebounce;
    }

    if (throttle === "") {
      throttle = defaultThrottle;
    }

    let value = debounce || throttle;

    switch (value) {
      case null:
        return callback();

      case "blur":
        if (this.once(el, "debounce-blur")) {
          el.addEventListener("blur", () => callback());
        }

        return;

      default:
        let timeout = parseInt(value);

        let trigger = () => throttle ? this.deletePrivate(el, THROTTLED) : callback();

        let currentCycle = this.incCycle(el, DEBOUNCE_TRIGGER, trigger);

        if (isNaN(timeout)) {
          return logError(`invalid throttle/debounce value: ${value}`);
        }

        if (throttle) {
          let newKeyDown = false;

          if (event.type === "keydown") {
            let prevKey = this.private(el, DEBOUNCE_PREV_KEY);
            this.putPrivate(el, DEBOUNCE_PREV_KEY, event.key);
            newKeyDown = prevKey !== event.key;
          }

          if (!newKeyDown && this.private(el, THROTTLED)) {
            return false;
          } else {
            callback();
            this.putPrivate(el, THROTTLED, true);
            setTimeout(() => this.triggerCycle(el, DEBOUNCE_TRIGGER), timeout);
          }
        } else {
          setTimeout(() => this.triggerCycle(el, DEBOUNCE_TRIGGER, currentCycle), timeout);
        }

        let form = el.form;

        if (form && this.once(form, "bind-debounce")) {
          form.addEventListener("submit", () => {
            Array.from(new FormData(form).entries(), ([name]) => {
              let input = form.querySelector(`[name="${name}"]`);
              this.incCycle(input, DEBOUNCE_TRIGGER);
              this.deletePrivate(input, THROTTLED);
            });
          });
        }

        if (this.once(el, "bind-debounce")) {
          el.addEventListener("blur", () => this.triggerCycle(el, DEBOUNCE_TRIGGER));
        }

    }
  },

  triggerCycle(el, key, currentCycle) {
    let [cycle, trigger] = this.private(el, key);

    if (!currentCycle) {
      currentCycle = cycle;
    }

    if (currentCycle === cycle) {
      this.incCycle(el, key);
      trigger();
    }
  },

  once(el, key) {
    if (this.private(el, key) === true) {
      return false;
    }

    this.putPrivate(el, key, true);
    return true;
  },

  incCycle(el, key, trigger = function () {}) {
    let [currentCycle] = this.private(el, key) || [0, trigger];
    currentCycle++;
    this.putPrivate(el, key, [currentCycle, trigger]);
    return currentCycle;
  },

  discardError(container, el, phxFeedbackFor) {
    let field = el.getAttribute && el.getAttribute(phxFeedbackFor);
    let input = field && container.querySelector(`[id="${field}"], [name="${field}"]`);

    if (!input) {
      return;
    }

    if (!(this.private(input, PHX_HAS_FOCUSED) || this.private(input.form, PHX_HAS_SUBMITTED))) {
      el.classList.add(PHX_NO_FEEDBACK_CLASS);
    }
  },

  showError(inputEl, phxFeedbackFor) {
    if (inputEl.id || inputEl.name) {
      this.all(inputEl.form, `[${phxFeedbackFor}="${inputEl.id}"], [${phxFeedbackFor}="${inputEl.name}"]`, el => {
        this.removeClass(el, PHX_NO_FEEDBACK_CLASS);
      });
    }
  },

  isPhxChild(node) {
    return node.getAttribute && node.getAttribute(PHX_PARENT_ID);
  },

  dispatchEvent(target, eventString, detail = {}) {
    let event = new CustomEvent(eventString, {
      bubbles: true,
      cancelable: true,
      detail
    });
    target.dispatchEvent(event);
  },

  cloneNode(node, html) {
    if (typeof html === "undefined") {
      return node.cloneNode(true);
    } else {
      let cloned = node.cloneNode(false);
      cloned.innerHTML = html;
      return cloned;
    }
  },

  mergeAttrs(target, source, opts = {}) {
    let exclude = opts.exclude || [];
    let isIgnored = opts.isIgnored;
    let sourceAttrs = source.attributes;

    for (let i = sourceAttrs.length - 1; i >= 0; i--) {
      let name = sourceAttrs[i].name;

      if (exclude.indexOf(name) < 0) {
        target.setAttribute(name, source.getAttribute(name));
      }
    }

    let targetAttrs = target.attributes;

    for (let i = targetAttrs.length - 1; i >= 0; i--) {
      let name = targetAttrs[i].name;

      if (isIgnored) {
        if (name.startsWith("data-") && !source.hasAttribute(name)) {
          target.removeAttribute(name);
        }
      } else {
        if (!source.hasAttribute(name)) {
          target.removeAttribute(name);
        }
      }
    }
  },

  mergeFocusedInput(target, source) {
    if (!(target instanceof HTMLSelectElement)) {
      DOM.mergeAttrs(target, source, {
        except: ["value"]
      });
    }

    if (source.readOnly) {
      target.setAttribute("readonly", true);
    } else {
      target.removeAttribute("readonly");
    }
  },

  hasSelectionRange(el) {
    return el.setSelectionRange && (el.type === "text" || el.type === "textarea");
  },

  restoreFocus(focused, selectionStart, selectionEnd) {
    if (!DOM.isTextualInput(focused)) {
      return;
    }

    let wasFocused = focused.matches(":focus");

    if (focused.readOnly) {
      focused.blur();
    }

    if (!wasFocused) {
      focused.focus();
    }

    if (this.hasSelectionRange(focused)) {
      focused.setSelectionRange(selectionStart, selectionEnd);
    }
  },

  isFormInput(el) {
    return /^(?:input|select|textarea)$/i.test(el.tagName) && el.type !== "button";
  },

  syncAttrsToProps(el) {
    if (el instanceof HTMLInputElement && CHECKABLE_INPUTS.indexOf(el.type.toLocaleLowerCase()) >= 0) {
      el.checked = el.getAttribute("checked") !== null;
    }
  },

  syncPropsToAttrs(el) {
    if (el instanceof HTMLSelectElement) {
      let selectedItem = el.options.item(el.selectedIndex);

      if (selectedItem && selectedItem.getAttribute("selected") === null) {
        selectedItem.setAttribute("selected", "");
      }
    }
  },

  isTextualInput(el) {
    return FOCUSABLE_INPUTS.indexOf(el.type) >= 0;
  },

  isNowTriggerFormExternal(el, phxTriggerExternal) {
    return el.getAttribute && el.getAttribute(phxTriggerExternal) !== null;
  },

  syncPendingRef(fromEl, toEl, disableWith) {
    let ref = fromEl.getAttribute(PHX_REF);

    if (ref === null) {
      return true;
    }

    if (DOM.isFormInput(fromEl) || fromEl.getAttribute(disableWith) !== null) {
      if (DOM.isUploadInput(fromEl)) {
        DOM.mergeAttrs(fromEl, toEl, {
          isIgnored: true
        });
      }

      DOM.putPrivate(fromEl, PHX_REF, toEl);
      return false;
    } else {
      PHX_EVENT_CLASSES.forEach(className => {
        fromEl.classList.contains(className) && toEl.classList.add(className);
      });
      toEl.setAttribute(PHX_REF, ref);
      return true;
    }
  },

  cleanChildNodes(container, phxUpdate) {
    if (DOM.isPhxUpdate(container, phxUpdate, ["append", "prepend"])) {
      let toRemove = [];
      container.childNodes.forEach(childNode => {
        if (!childNode.id) {
          let isEmptyTextNode = childNode.nodeType === Node.TEXT_NODE && childNode.nodeValue.trim() === "";

          if (!isEmptyTextNode) {
            logError(`only HTML element tags with an id are allowed inside containers with phx-update.

removing illegal node: "${(childNode.outerHTML || childNode.nodeValue).trim()}"

`);
          }

          toRemove.push(childNode);
        }
      });
      toRemove.forEach(childNode => childNode.remove());
    }
  },

  replaceRootContainer(container, tagName, attrs) {
    let retainedAttrs = new Set(["id", PHX_SESSION, PHX_STATIC, PHX_MAIN]);

    if (container.tagName.toLowerCase() === tagName.toLowerCase()) {
      Array.from(container.attributes).filter(attr => !retainedAttrs.has(attr.name.toLowerCase())).forEach(attr => container.removeAttribute(attr.name));
      Object.keys(attrs).filter(name => !retainedAttrs.has(name.toLowerCase())).forEach(attr => container.setAttribute(attr, attrs[attr]));
      return container;
    } else {
      let newContainer = document.createElement(tagName);
      Object.keys(attrs).forEach(attr => newContainer.setAttribute(attr, attrs[attr]));
      retainedAttrs.forEach(attr => newContainer.setAttribute(attr, container.getAttribute(attr)));
      newContainer.innerHTML = container.innerHTML;
      container.replaceWith(newContainer);
      return newContainer;
    }
  }

};
var dom_default = DOM; // js/phoenix_live_view/upload_entry.js

var UploadEntry = class {
  static isActive(fileEl, file) {
    let isNew = file._phxRef === void 0;
    let activeRefs = fileEl.getAttribute(PHX_ACTIVE_ENTRY_REFS).split(",");
    let isActive = activeRefs.indexOf(LiveUploader.genFileRef(file)) >= 0;
    return file.size > 0 && (isNew || isActive);
  }

  static isPreflighted(fileEl, file) {
    let preflightedRefs = fileEl.getAttribute(PHX_PREFLIGHTED_REFS).split(",");
    let isPreflighted = preflightedRefs.indexOf(LiveUploader.genFileRef(file)) >= 0;
    return isPreflighted && this.isActive(fileEl, file);
  }

  constructor(fileEl, file, view) {
    this.ref = LiveUploader.genFileRef(file);
    this.fileEl = fileEl;
    this.file = file;
    this.view = view;
    this.meta = null;
    this._isCancelled = false;
    this._isDone = false;
    this._progress = 0;
    this._lastProgressSent = -1;

    this._onDone = function () {};

    this._onElUpdated = this.onElUpdated.bind(this);
    this.fileEl.addEventListener(PHX_LIVE_FILE_UPDATED, this._onElUpdated);
  }

  metadata() {
    return this.meta;
  }

  progress(progress) {
    this._progress = Math.floor(progress);

    if (this._progress > this._lastProgressSent) {
      if (this._progress >= 100) {
        this._progress = 100;
        this._lastProgressSent = 100;
        this._isDone = true;
        this.view.pushFileProgress(this.fileEl, this.ref, 100, () => {
          LiveUploader.untrackFile(this.fileEl, this.file);

          this._onDone();
        });
      } else {
        this._lastProgressSent = this._progress;
        this.view.pushFileProgress(this.fileEl, this.ref, this._progress);
      }
    }
  }

  cancel() {
    this._isCancelled = true;
    this._isDone = true;

    this._onDone();
  }

  isDone() {
    return this._isDone;
  }

  error(reason = "failed") {
    this.view.pushFileProgress(this.fileEl, this.ref, {
      error: reason
    });
    LiveUploader.clearFiles(this.fileEl);
  }

  onDone(callback) {
    this._onDone = () => {
      this.fileEl.removeEventListener(PHX_LIVE_FILE_UPDATED, this._onElUpdated);
      callback();
    };
  }

  onElUpdated() {
    let activeRefs = this.fileEl.getAttribute(PHX_ACTIVE_ENTRY_REFS).split(",");

    if (activeRefs.indexOf(this.ref) === -1) {
      this.cancel();
    }
  }

  toPreflightPayload() {
    return {
      last_modified: this.file.lastModified,
      name: this.file.name,
      size: this.file.size,
      type: this.file.type,
      ref: this.ref
    };
  }

  uploader(uploaders) {
    if (this.meta.uploader) {
      let callback = uploaders[this.meta.uploader] || logError(`no uploader configured for ${this.meta.uploader}`);
      return {
        name: this.meta.uploader,
        callback
      };
    } else {
      return {
        name: "channel",
        callback: channelUploader
      };
    }
  }

  zipPostFlight(resp) {
    this.meta = resp.entries[this.ref];

    if (!this.meta) {
      logError(`no preflight upload response returned with ref ${this.ref}`, {
        input: this.fileEl,
        response: resp
      });
    }
  }

}; // js/phoenix_live_view/live_uploader.js

var liveUploaderFileRef = 0;
var LiveUploader = class {
  static genFileRef(file) {
    let ref = file._phxRef;

    if (ref !== void 0) {
      return ref;
    } else {
      file._phxRef = (liveUploaderFileRef++).toString();
      return file._phxRef;
    }
  }

  static getEntryDataURL(inputEl, ref, callback) {
    let file = this.activeFiles(inputEl).find(file2 => this.genFileRef(file2) === ref);
    callback(URL.createObjectURL(file));
  }

  static hasUploadsInProgress(formEl) {
    let active = 0;
    dom_default.findUploadInputs(formEl).forEach(input => {
      if (input.getAttribute(PHX_PREFLIGHTED_REFS) !== input.getAttribute(PHX_DONE_REFS)) {
        active++;
      }
    });
    return active > 0;
  }

  static serializeUploads(inputEl) {
    let files = this.activeFiles(inputEl);
    let fileData = {};
    files.forEach(file => {
      let entry = {
        path: inputEl.name
      };
      let uploadRef = inputEl.getAttribute(PHX_UPLOAD_REF);
      fileData[uploadRef] = fileData[uploadRef] || [];
      entry.ref = this.genFileRef(file);
      entry.name = file.name || entry.ref;
      entry.type = file.type;
      entry.size = file.size;
      fileData[uploadRef].push(entry);
    });
    return fileData;
  }

  static clearFiles(inputEl) {
    inputEl.value = null;
    inputEl.removeAttribute(PHX_UPLOAD_REF);
    dom_default.putPrivate(inputEl, "files", []);
  }

  static untrackFile(inputEl, file) {
    dom_default.putPrivate(inputEl, "files", dom_default.private(inputEl, "files").filter(f => !Object.is(f, file)));
  }

  static trackFiles(inputEl, files) {
    if (inputEl.getAttribute("multiple") !== null) {
      let newFiles = files.filter(file => !this.activeFiles(inputEl).find(f => Object.is(f, file)));
      dom_default.putPrivate(inputEl, "files", this.activeFiles(inputEl).concat(newFiles));
      inputEl.value = null;
    } else {
      dom_default.putPrivate(inputEl, "files", files);
    }
  }

  static activeFileInputs(formEl) {
    let fileInputs = dom_default.findUploadInputs(formEl);
    return Array.from(fileInputs).filter(el => el.files && this.activeFiles(el).length > 0);
  }

  static activeFiles(input) {
    return (dom_default.private(input, "files") || []).filter(f => UploadEntry.isActive(input, f));
  }

  static inputsAwaitingPreflight(formEl) {
    let fileInputs = dom_default.findUploadInputs(formEl);
    return Array.from(fileInputs).filter(input => this.filesAwaitingPreflight(input).length > 0);
  }

  static filesAwaitingPreflight(input) {
    return this.activeFiles(input).filter(f => !UploadEntry.isPreflighted(input, f));
  }

  constructor(inputEl, view, onComplete) {
    this.view = view;
    this.onComplete = onComplete;
    this._entries = Array.from(LiveUploader.filesAwaitingPreflight(inputEl) || []).map(file => new UploadEntry(inputEl, file, view));
    this.numEntriesInProgress = this._entries.length;
  }

  entries() {
    return this._entries;
  }

  initAdapterUpload(resp, onError, liveSocket) {
    this._entries = this._entries.map(entry => {
      entry.zipPostFlight(resp);
      entry.onDone(() => {
        this.numEntriesInProgress--;

        if (this.numEntriesInProgress === 0) {
          this.onComplete();
        }
      });
      return entry;
    });

    let groupedEntries = this._entries.reduce((acc, entry) => {
      let {
        name,
        callback
      } = entry.uploader(liveSocket.uploaders);
      acc[name] = acc[name] || {
        callback,
        entries: []
      };
      acc[name].entries.push(entry);
      return acc;
    }, {});

    for (let name in groupedEntries) {
      let {
        callback,
        entries
      } = groupedEntries[name];
      callback(entries, onError, resp, liveSocket);
    }
  }

}; // js/phoenix_live_view/hooks.js

var Hooks = {
  LiveFileUpload: {
    activeRefs() {
      return this.el.getAttribute(PHX_ACTIVE_ENTRY_REFS);
    },

    preflightedRefs() {
      return this.el.getAttribute(PHX_PREFLIGHTED_REFS);
    },

    mounted() {
      this.preflightedWas = this.preflightedRefs();
    },

    updated() {
      let newPreflights = this.preflightedRefs();

      if (this.preflightedWas !== newPreflights) {
        this.preflightedWas = newPreflights;

        if (newPreflights === "") {
          this.__view.cancelSubmit(this.el.form);
        }
      }

      if (this.activeRefs() === "") {
        this.el.value = null;
      }

      this.el.dispatchEvent(new CustomEvent(PHX_LIVE_FILE_UPDATED));
    }

  },
  LiveImgPreview: {
    mounted() {
      this.ref = this.el.getAttribute("data-phx-entry-ref");
      this.inputEl = document.getElementById(this.el.getAttribute(PHX_UPLOAD_REF));
      LiveUploader.getEntryDataURL(this.inputEl, this.ref, url => {
        this.url = url;
        this.el.src = url;
      });
    },

    destroyed() {
      URL.revokeObjectURL(this.url);
    }

  }
};
var hooks_default = Hooks; // js/phoenix_live_view/dom_post_morph_restorer.js

var DOMPostMorphRestorer = class {
  constructor(containerBefore, containerAfter, updateType) {
    let idsBefore = new Set();
    let idsAfter = new Set([...containerAfter.children].map(child => child.id));
    let elementsToModify = [];
    Array.from(containerBefore.children).forEach(child => {
      if (child.id) {
        idsBefore.add(child.id);

        if (idsAfter.has(child.id)) {
          let previousElementId = child.previousElementSibling && child.previousElementSibling.id;
          elementsToModify.push({
            elementId: child.id,
            previousElementId
          });
        }
      }
    });
    this.containerId = containerAfter.id;
    this.updateType = updateType;
    this.elementsToModify = elementsToModify;
    this.elementIdsToAdd = [...idsAfter].filter(id => !idsBefore.has(id));
  }

  perform() {
    let container = dom_default.byId(this.containerId);
    this.elementsToModify.forEach(elementToModify => {
      if (elementToModify.previousElementId) {
        maybe(document.getElementById(elementToModify.previousElementId), previousElem => {
          maybe(document.getElementById(elementToModify.elementId), elem => {
            let isInRightPlace = elem.previousElementSibling && elem.previousElementSibling.id == previousElem.id;

            if (!isInRightPlace) {
              previousElem.insertAdjacentElement("afterend", elem);
            }
          });
        });
      } else {
        maybe(document.getElementById(elementToModify.elementId), elem => {
          let isInRightPlace = elem.previousElementSibling == null;

          if (!isInRightPlace) {
            container.insertAdjacentElement("afterbegin", elem);
          }
        });
      }
    });

    if (this.updateType == "prepend") {
      this.elementIdsToAdd.reverse().forEach(elemId => {
        maybe(document.getElementById(elemId), elem => container.insertAdjacentElement("afterbegin", elem));
      });
    }
  }

}; // node_modules/morphdom/dist/morphdom-esm.js

var DOCUMENT_FRAGMENT_NODE = 11;

function morphAttrs(fromNode, toNode) {
  var toNodeAttrs = toNode.attributes;
  var attr;
  var attrName;
  var attrNamespaceURI;
  var attrValue;
  var fromValue;

  if (toNode.nodeType === DOCUMENT_FRAGMENT_NODE || fromNode.nodeType === DOCUMENT_FRAGMENT_NODE) {
    return;
  }

  for (var i = toNodeAttrs.length - 1; i >= 0; i--) {
    attr = toNodeAttrs[i];
    attrName = attr.name;
    attrNamespaceURI = attr.namespaceURI;
    attrValue = attr.value;

    if (attrNamespaceURI) {
      attrName = attr.localName || attrName;
      fromValue = fromNode.getAttributeNS(attrNamespaceURI, attrName);

      if (fromValue !== attrValue) {
        if (attr.prefix === "xmlns") {
          attrName = attr.name;
        }

        fromNode.setAttributeNS(attrNamespaceURI, attrName, attrValue);
      }
    } else {
      fromValue = fromNode.getAttribute(attrName);

      if (fromValue !== attrValue) {
        fromNode.setAttribute(attrName, attrValue);
      }
    }
  }

  var fromNodeAttrs = fromNode.attributes;

  for (var d = fromNodeAttrs.length - 1; d >= 0; d--) {
    attr = fromNodeAttrs[d];
    attrName = attr.name;
    attrNamespaceURI = attr.namespaceURI;

    if (attrNamespaceURI) {
      attrName = attr.localName || attrName;

      if (!toNode.hasAttributeNS(attrNamespaceURI, attrName)) {
        fromNode.removeAttributeNS(attrNamespaceURI, attrName);
      }
    } else {
      if (!toNode.hasAttribute(attrName)) {
        fromNode.removeAttribute(attrName);
      }
    }
  }
}

var range;
var NS_XHTML = "http://www.w3.org/1999/xhtml";
var doc = typeof document === "undefined" ? void 0 : document;
var HAS_TEMPLATE_SUPPORT = !!doc && "content" in doc.createElement("template");
var HAS_RANGE_SUPPORT = !!doc && doc.createRange && "createContextualFragment" in doc.createRange();

function createFragmentFromTemplate(str) {
  var template = doc.createElement("template");
  template.innerHTML = str;
  return template.content.childNodes[0];
}

function createFragmentFromRange(str) {
  if (!range) {
    range = doc.createRange();
    range.selectNode(doc.body);
  }

  var fragment = range.createContextualFragment(str);
  return fragment.childNodes[0];
}

function createFragmentFromWrap(str) {
  var fragment = doc.createElement("body");
  fragment.innerHTML = str;
  return fragment.childNodes[0];
}

function toElement(str) {
  str = str.trim();

  if (HAS_TEMPLATE_SUPPORT) {
    return createFragmentFromTemplate(str);
  } else if (HAS_RANGE_SUPPORT) {
    return createFragmentFromRange(str);
  }

  return createFragmentFromWrap(str);
}

function compareNodeNames(fromEl, toEl) {
  var fromNodeName = fromEl.nodeName;
  var toNodeName = toEl.nodeName;
  var fromCodeStart, toCodeStart;

  if (fromNodeName === toNodeName) {
    return true;
  }

  fromCodeStart = fromNodeName.charCodeAt(0);
  toCodeStart = toNodeName.charCodeAt(0);

  if (fromCodeStart <= 90 && toCodeStart >= 97) {
    return fromNodeName === toNodeName.toUpperCase();
  } else if (toCodeStart <= 90 && fromCodeStart >= 97) {
    return toNodeName === fromNodeName.toUpperCase();
  } else {
    return false;
  }
}

function createElementNS(name, namespaceURI) {
  return !namespaceURI || namespaceURI === NS_XHTML ? doc.createElement(name) : doc.createElementNS(namespaceURI, name);
}

function moveChildren(fromEl, toEl) {
  var curChild = fromEl.firstChild;

  while (curChild) {
    var nextChild = curChild.nextSibling;
    toEl.appendChild(curChild);
    curChild = nextChild;
  }

  return toEl;
}

function syncBooleanAttrProp(fromEl, toEl, name) {
  if (fromEl[name] !== toEl[name]) {
    fromEl[name] = toEl[name];

    if (fromEl[name]) {
      fromEl.setAttribute(name, "");
    } else {
      fromEl.removeAttribute(name);
    }
  }
}

var specialElHandlers = {
  OPTION: function (fromEl, toEl) {
    var parentNode = fromEl.parentNode;

    if (parentNode) {
      var parentName = parentNode.nodeName.toUpperCase();

      if (parentName === "OPTGROUP") {
        parentNode = parentNode.parentNode;
        parentName = parentNode && parentNode.nodeName.toUpperCase();
      }

      if (parentName === "SELECT" && !parentNode.hasAttribute("multiple")) {
        if (fromEl.hasAttribute("selected") && !toEl.selected) {
          fromEl.setAttribute("selected", "selected");
          fromEl.removeAttribute("selected");
        }

        parentNode.selectedIndex = -1;
      }
    }

    syncBooleanAttrProp(fromEl, toEl, "selected");
  },
  INPUT: function (fromEl, toEl) {
    syncBooleanAttrProp(fromEl, toEl, "checked");
    syncBooleanAttrProp(fromEl, toEl, "disabled");

    if (fromEl.value !== toEl.value) {
      fromEl.value = toEl.value;
    }

    if (!toEl.hasAttribute("value")) {
      fromEl.removeAttribute("value");
    }
  },
  TEXTAREA: function (fromEl, toEl) {
    var newValue = toEl.value;

    if (fromEl.value !== newValue) {
      fromEl.value = newValue;
    }

    var firstChild = fromEl.firstChild;

    if (firstChild) {
      var oldValue = firstChild.nodeValue;

      if (oldValue == newValue || !newValue && oldValue == fromEl.placeholder) {
        return;
      }

      firstChild.nodeValue = newValue;
    }
  },
  SELECT: function (fromEl, toEl) {
    if (!toEl.hasAttribute("multiple")) {
      var selectedIndex = -1;
      var i = 0;
      var curChild = fromEl.firstChild;
      var optgroup;
      var nodeName;

      while (curChild) {
        nodeName = curChild.nodeName && curChild.nodeName.toUpperCase();

        if (nodeName === "OPTGROUP") {
          optgroup = curChild;
          curChild = optgroup.firstChild;
        } else {
          if (nodeName === "OPTION") {
            if (curChild.hasAttribute("selected")) {
              selectedIndex = i;
              break;
            }

            i++;
          }

          curChild = curChild.nextSibling;

          if (!curChild && optgroup) {
            curChild = optgroup.nextSibling;
            optgroup = null;
          }
        }
      }

      fromEl.selectedIndex = selectedIndex;
    }
  }
};
var ELEMENT_NODE = 1;
var DOCUMENT_FRAGMENT_NODE$1 = 11;
var TEXT_NODE = 3;
var COMMENT_NODE = 8;

function noop() {}

function defaultGetNodeKey(node) {
  if (node) {
    return node.getAttribute && node.getAttribute("id") || node.id;
  }
}

function morphdomFactory(morphAttrs2) {
  return function morphdom2(fromNode, toNode, options) {
    if (!options) {
      options = {};
    }

    if (typeof toNode === "string") {
      if (fromNode.nodeName === "#document" || fromNode.nodeName === "HTML" || fromNode.nodeName === "BODY") {
        var toNodeHtml = toNode;
        toNode = doc.createElement("html");
        toNode.innerHTML = toNodeHtml;
      } else {
        toNode = toElement(toNode);
      }
    }

    var getNodeKey = options.getNodeKey || defaultGetNodeKey;
    var onBeforeNodeAdded = options.onBeforeNodeAdded || noop;
    var onNodeAdded = options.onNodeAdded || noop;
    var onBeforeElUpdated = options.onBeforeElUpdated || noop;
    var onElUpdated = options.onElUpdated || noop;
    var onBeforeNodeDiscarded = options.onBeforeNodeDiscarded || noop;
    var onNodeDiscarded = options.onNodeDiscarded || noop;
    var onBeforeElChildrenUpdated = options.onBeforeElChildrenUpdated || noop;
    var childrenOnly = options.childrenOnly === true;
    var fromNodesLookup = Object.create(null);
    var keyedRemovalList = [];

    function addKeyedRemoval(key) {
      keyedRemovalList.push(key);
    }

    function walkDiscardedChildNodes(node, skipKeyedNodes) {
      if (node.nodeType === ELEMENT_NODE) {
        var curChild = node.firstChild;

        while (curChild) {
          var key = void 0;

          if (skipKeyedNodes && (key = getNodeKey(curChild))) {
            addKeyedRemoval(key);
          } else {
            onNodeDiscarded(curChild);

            if (curChild.firstChild) {
              walkDiscardedChildNodes(curChild, skipKeyedNodes);
            }
          }

          curChild = curChild.nextSibling;
        }
      }
    }

    function removeNode(node, parentNode, skipKeyedNodes) {
      if (onBeforeNodeDiscarded(node) === false) {
        return;
      }

      if (parentNode) {
        parentNode.removeChild(node);
      }

      onNodeDiscarded(node);
      walkDiscardedChildNodes(node, skipKeyedNodes);
    }

    function indexTree(node) {
      if (node.nodeType === ELEMENT_NODE || node.nodeType === DOCUMENT_FRAGMENT_NODE$1) {
        var curChild = node.firstChild;

        while (curChild) {
          var key = getNodeKey(curChild);

          if (key) {
            fromNodesLookup[key] = curChild;
          }

          indexTree(curChild);
          curChild = curChild.nextSibling;
        }
      }
    }

    indexTree(fromNode);

    function handleNodeAdded(el) {
      onNodeAdded(el);
      var curChild = el.firstChild;

      while (curChild) {
        var nextSibling = curChild.nextSibling;
        var key = getNodeKey(curChild);

        if (key) {
          var unmatchedFromEl = fromNodesLookup[key];

          if (unmatchedFromEl && compareNodeNames(curChild, unmatchedFromEl)) {
            curChild.parentNode.replaceChild(unmatchedFromEl, curChild);
            morphEl(unmatchedFromEl, curChild);
          } else {
            handleNodeAdded(curChild);
          }
        } else {
          handleNodeAdded(curChild);
        }

        curChild = nextSibling;
      }
    }

    function cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey) {
      while (curFromNodeChild) {
        var fromNextSibling = curFromNodeChild.nextSibling;

        if (curFromNodeKey = getNodeKey(curFromNodeChild)) {
          addKeyedRemoval(curFromNodeKey);
        } else {
          removeNode(curFromNodeChild, fromEl, true);
        }

        curFromNodeChild = fromNextSibling;
      }
    }

    function morphEl(fromEl, toEl, childrenOnly2) {
      var toElKey = getNodeKey(toEl);

      if (toElKey) {
        delete fromNodesLookup[toElKey];
      }

      if (!childrenOnly2) {
        if (onBeforeElUpdated(fromEl, toEl) === false) {
          return;
        }

        morphAttrs2(fromEl, toEl);
        onElUpdated(fromEl);

        if (onBeforeElChildrenUpdated(fromEl, toEl) === false) {
          return;
        }
      }

      if (fromEl.nodeName !== "TEXTAREA") {
        morphChildren(fromEl, toEl);
      } else {
        specialElHandlers.TEXTAREA(fromEl, toEl);
      }
    }

    function morphChildren(fromEl, toEl) {
      var curToNodeChild = toEl.firstChild;
      var curFromNodeChild = fromEl.firstChild;
      var curToNodeKey;
      var curFromNodeKey;
      var fromNextSibling;
      var toNextSibling;
      var matchingFromEl;

      outer: while (curToNodeChild) {
        toNextSibling = curToNodeChild.nextSibling;
        curToNodeKey = getNodeKey(curToNodeChild);

        while (curFromNodeChild) {
          fromNextSibling = curFromNodeChild.nextSibling;

          if (curToNodeChild.isSameNode && curToNodeChild.isSameNode(curFromNodeChild)) {
            curToNodeChild = toNextSibling;
            curFromNodeChild = fromNextSibling;
            continue outer;
          }

          curFromNodeKey = getNodeKey(curFromNodeChild);
          var curFromNodeType = curFromNodeChild.nodeType;
          var isCompatible = void 0;

          if (curFromNodeType === curToNodeChild.nodeType) {
            if (curFromNodeType === ELEMENT_NODE) {
              if (curToNodeKey) {
                if (curToNodeKey !== curFromNodeKey) {
                  if (matchingFromEl = fromNodesLookup[curToNodeKey]) {
                    if (fromNextSibling === matchingFromEl) {
                      isCompatible = false;
                    } else {
                      fromEl.insertBefore(matchingFromEl, curFromNodeChild);

                      if (curFromNodeKey) {
                        addKeyedRemoval(curFromNodeKey);
                      } else {
                        removeNode(curFromNodeChild, fromEl, true);
                      }

                      curFromNodeChild = matchingFromEl;
                    }
                  } else {
                    isCompatible = false;
                  }
                }
              } else if (curFromNodeKey) {
                isCompatible = false;
              }

              isCompatible = isCompatible !== false && compareNodeNames(curFromNodeChild, curToNodeChild);

              if (isCompatible) {
                morphEl(curFromNodeChild, curToNodeChild);
              }
            } else if (curFromNodeType === TEXT_NODE || curFromNodeType == COMMENT_NODE) {
              isCompatible = true;

              if (curFromNodeChild.nodeValue !== curToNodeChild.nodeValue) {
                curFromNodeChild.nodeValue = curToNodeChild.nodeValue;
              }
            }
          }

          if (isCompatible) {
            curToNodeChild = toNextSibling;
            curFromNodeChild = fromNextSibling;
            continue outer;
          }

          if (curFromNodeKey) {
            addKeyedRemoval(curFromNodeKey);
          } else {
            removeNode(curFromNodeChild, fromEl, true);
          }

          curFromNodeChild = fromNextSibling;
        }

        if (curToNodeKey && (matchingFromEl = fromNodesLookup[curToNodeKey]) && compareNodeNames(matchingFromEl, curToNodeChild)) {
          fromEl.appendChild(matchingFromEl);
          morphEl(matchingFromEl, curToNodeChild);
        } else {
          var onBeforeNodeAddedResult = onBeforeNodeAdded(curToNodeChild);

          if (onBeforeNodeAddedResult !== false) {
            if (onBeforeNodeAddedResult) {
              curToNodeChild = onBeforeNodeAddedResult;
            }

            if (curToNodeChild.actualize) {
              curToNodeChild = curToNodeChild.actualize(fromEl.ownerDocument || doc);
            }

            fromEl.appendChild(curToNodeChild);
            handleNodeAdded(curToNodeChild);
          }
        }

        curToNodeChild = toNextSibling;
        curFromNodeChild = fromNextSibling;
      }

      cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey);
      var specialElHandler = specialElHandlers[fromEl.nodeName];

      if (specialElHandler) {
        specialElHandler(fromEl, toEl);
      }
    }

    var morphedNode = fromNode;
    var morphedNodeType = morphedNode.nodeType;
    var toNodeType = toNode.nodeType;

    if (!childrenOnly) {
      if (morphedNodeType === ELEMENT_NODE) {
        if (toNodeType === ELEMENT_NODE) {
          if (!compareNodeNames(fromNode, toNode)) {
            onNodeDiscarded(fromNode);
            morphedNode = moveChildren(fromNode, createElementNS(toNode.nodeName, toNode.namespaceURI));
          }
        } else {
          morphedNode = toNode;
        }
      } else if (morphedNodeType === TEXT_NODE || morphedNodeType === COMMENT_NODE) {
        if (toNodeType === morphedNodeType) {
          if (morphedNode.nodeValue !== toNode.nodeValue) {
            morphedNode.nodeValue = toNode.nodeValue;
          }

          return morphedNode;
        } else {
          morphedNode = toNode;
        }
      }
    }

    if (morphedNode === toNode) {
      onNodeDiscarded(fromNode);
    } else {
      if (toNode.isSameNode && toNode.isSameNode(morphedNode)) {
        return;
      }

      morphEl(morphedNode, toNode, childrenOnly);

      if (keyedRemovalList) {
        for (var i = 0, len = keyedRemovalList.length; i < len; i++) {
          var elToRemove = fromNodesLookup[keyedRemovalList[i]];

          if (elToRemove) {
            removeNode(elToRemove, elToRemove.parentNode, false);
          }
        }
      }
    }

    if (!childrenOnly && morphedNode !== fromNode && fromNode.parentNode) {
      if (morphedNode.actualize) {
        morphedNode = morphedNode.actualize(fromNode.ownerDocument || doc);
      }

      fromNode.parentNode.replaceChild(morphedNode, fromNode);
    }

    return morphedNode;
  };
}

var morphdom = morphdomFactory(morphAttrs);
var morphdom_esm_default = morphdom; // js/phoenix_live_view/dom_patch.js

var DOMPatch = class {
  static patchEl(fromEl, toEl, activeElement) {
    morphdom_esm_default(fromEl, toEl, {
      childrenOnly: false,
      onBeforeElUpdated: (fromEl2, toEl2) => {
        if (activeElement && activeElement.isSameNode(fromEl2) && dom_default.isFormInput(fromEl2)) {
          dom_default.mergeFocusedInput(fromEl2, toEl2);
          return false;
        }
      }
    });
  }

  constructor(view, container, id, html, targetCID) {
    this.view = view;
    this.liveSocket = view.liveSocket;
    this.container = container;
    this.id = id;
    this.rootID = view.root.id;
    this.html = html;
    this.targetCID = targetCID;
    this.cidPatch = isCid(this.targetCID);
    this.callbacks = {
      beforeadded: [],
      beforeupdated: [],
      beforephxChildAdded: [],
      afteradded: [],
      afterupdated: [],
      afterdiscarded: [],
      afterphxChildAdded: []
    };
  }

  before(kind, callback) {
    this.callbacks[`before${kind}`].push(callback);
  }

  after(kind, callback) {
    this.callbacks[`after${kind}`].push(callback);
  }

  trackBefore(kind, ...args) {
    this.callbacks[`before${kind}`].forEach(callback => callback(...args));
  }

  trackAfter(kind, ...args) {
    this.callbacks[`after${kind}`].forEach(callback => callback(...args));
  }

  markPrunableContentForRemoval() {
    dom_default.all(this.container, "[phx-update=append] > *, [phx-update=prepend] > *", el => {
      el.setAttribute(PHX_REMOVE, "");
    });
  }

  perform() {
    let {
      view,
      liveSocket,
      container,
      html
    } = this;
    let targetContainer = this.isCIDPatch() ? this.targetCIDContainer(html) : container;

    if (this.isCIDPatch() && !targetContainer) {
      return;
    }

    let focused = liveSocket.getActiveElement();
    let {
      selectionStart,
      selectionEnd
    } = focused && dom_default.hasSelectionRange(focused) ? focused : {};
    let phxUpdate = liveSocket.binding(PHX_UPDATE);
    let phxFeedbackFor = liveSocket.binding(PHX_FEEDBACK_FOR);
    let disableWith = liveSocket.binding(PHX_DISABLE_WITH);
    let phxTriggerExternal = liveSocket.binding(PHX_TRIGGER_ACTION);
    let added = [];
    let updates = [];
    let appendPrependUpdates = [];
    let externalFormTriggered = null;
    let diffHTML = liveSocket.time("premorph container prep", () => {
      return this.buildDiffHTML(container, html, phxUpdate, targetContainer);
    });
    this.trackBefore("added", container);
    this.trackBefore("updated", container, container);
    liveSocket.time("morphdom", () => {
      morphdom_esm_default(targetContainer, diffHTML, {
        childrenOnly: targetContainer.getAttribute(PHX_COMPONENT) === null,
        getNodeKey: node => {
          return dom_default.isPhxDestroyed(node) ? null : node.id;
        },
        onBeforeNodeAdded: el => {
          this.trackBefore("added", el);
          return el;
        },
        onNodeAdded: el => {
          if (dom_default.isNowTriggerFormExternal(el, phxTriggerExternal)) {
            externalFormTriggered = el;
          }

          dom_default.discardError(targetContainer, el, phxFeedbackFor);

          if (dom_default.isPhxChild(el) && view.ownsElement(el)) {
            this.trackAfter("phxChildAdded", el);
          }

          added.push(el);
        },
        onNodeDiscarded: el => {
          if (dom_default.isPhxChild(el)) {
            liveSocket.destroyViewByEl(el);
          }

          this.trackAfter("discarded", el);
        },
        onBeforeNodeDiscarded: el => {
          if (el.getAttribute && el.getAttribute(PHX_REMOVE) !== null) {
            return true;
          }

          if (el.parentNode !== null && dom_default.isPhxUpdate(el.parentNode, phxUpdate, ["append", "prepend"]) && el.id) {
            return false;
          }

          if (this.skipCIDSibling(el)) {
            return false;
          }

          return true;
        },
        onElUpdated: el => {
          if (dom_default.isNowTriggerFormExternal(el, phxTriggerExternal)) {
            externalFormTriggered = el;
          }

          updates.push(el);
        },
        onBeforeElUpdated: (fromEl, toEl) => {
          dom_default.cleanChildNodes(toEl, phxUpdate);

          if (this.skipCIDSibling(toEl)) {
            return false;
          }

          if (dom_default.isIgnored(fromEl, phxUpdate)) {
            this.trackBefore("updated", fromEl, toEl);
            dom_default.mergeAttrs(fromEl, toEl, {
              isIgnored: true
            });
            updates.push(fromEl);
            return false;
          }

          if (fromEl.type === "number" && fromEl.validity && fromEl.validity.badInput) {
            return false;
          }

          if (!dom_default.syncPendingRef(fromEl, toEl, disableWith)) {
            if (dom_default.isUploadInput(fromEl)) {
              this.trackBefore("updated", fromEl, toEl);
              updates.push(fromEl);
            }

            return false;
          }

          if (dom_default.isPhxChild(toEl)) {
            let prevSession = fromEl.getAttribute(PHX_SESSION);
            dom_default.mergeAttrs(fromEl, toEl, {
              exclude: [PHX_STATIC]
            });

            if (prevSession !== "") {
              fromEl.setAttribute(PHX_SESSION, prevSession);
            }

            fromEl.setAttribute(PHX_ROOT_ID, this.rootID);
            return false;
          }

          dom_default.copyPrivates(toEl, fromEl);
          dom_default.discardError(targetContainer, toEl, phxFeedbackFor);
          dom_default.syncPropsToAttrs(toEl);
          let isFocusedFormEl = focused && fromEl.isSameNode(focused) && dom_default.isFormInput(fromEl);

          if (isFocusedFormEl && !this.forceFocusedSelectUpdate(fromEl, toEl)) {
            this.trackBefore("updated", fromEl, toEl);
            dom_default.mergeFocusedInput(fromEl, toEl);
            dom_default.syncAttrsToProps(fromEl);
            updates.push(fromEl);
            return false;
          } else {
            if (dom_default.isPhxUpdate(toEl, phxUpdate, ["append", "prepend"])) {
              appendPrependUpdates.push(new DOMPostMorphRestorer(fromEl, toEl, toEl.getAttribute(phxUpdate)));
            }

            dom_default.syncAttrsToProps(toEl);
            this.trackBefore("updated", fromEl, toEl);
            return true;
          }
        }
      });
    });

    if (liveSocket.isDebugEnabled()) {
      detectDuplicateIds();
    }

    if (appendPrependUpdates.length > 0) {
      liveSocket.time("post-morph append/prepend restoration", () => {
        appendPrependUpdates.forEach(update => update.perform());
      });
    }

    liveSocket.silenceEvents(() => dom_default.restoreFocus(focused, selectionStart, selectionEnd));
    dom_default.dispatchEvent(document, "phx:update");
    added.forEach(el => this.trackAfter("added", el));
    updates.forEach(el => this.trackAfter("updated", el));

    if (externalFormTriggered) {
      liveSocket.disconnect();
      externalFormTriggered.submit();
    }

    return true;
  }

  forceFocusedSelectUpdate(fromEl, toEl) {
    let isSelect = ["select", "select-one", "select-multiple"].find(t => t === fromEl.type);
    return fromEl.multiple === true || isSelect && fromEl.innerHTML != toEl.innerHTML;
  }

  isCIDPatch() {
    return this.cidPatch;
  }

  skipCIDSibling(el) {
    return el.nodeType === Node.ELEMENT_NODE && el.getAttribute(PHX_SKIP) !== null;
  }

  targetCIDContainer(html) {
    if (!this.isCIDPatch()) {
      return;
    }

    let [first, ...rest] = dom_default.findComponentNodeList(this.container, this.targetCID);

    if (rest.length === 0 && dom_default.childNodeLength(html) === 1) {
      return first;
    } else {
      return first && first.parentNode;
    }
  }

  buildDiffHTML(container, html, phxUpdate, targetContainer) {
    let isCIDPatch = this.isCIDPatch();
    let isCIDWithSingleRoot = isCIDPatch && targetContainer.getAttribute(PHX_COMPONENT) === this.targetCID.toString();

    if (!isCIDPatch || isCIDWithSingleRoot) {
      return html;
    } else {
      let diffContainer = null;
      let template = document.createElement("template");
      diffContainer = dom_default.cloneNode(targetContainer);
      let [firstComponent, ...rest] = dom_default.findComponentNodeList(diffContainer, this.targetCID);
      template.innerHTML = html;
      rest.forEach(el => el.remove());
      Array.from(diffContainer.childNodes).forEach(child => {
        if (child.id && child.nodeType === Node.ELEMENT_NODE && child.getAttribute(PHX_COMPONENT) !== this.targetCID.toString()) {
          child.setAttribute(PHX_SKIP, "");
          child.innerHTML = "";
        }
      });
      Array.from(template.content.childNodes).forEach(el => diffContainer.insertBefore(el, firstComponent));
      firstComponent.remove();
      return diffContainer.outerHTML;
    }
  }

}; // js/phoenix_live_view/rendered.js

var Rendered = class {
  static extract(diff) {
    let {
      [REPLY]: reply,
      [EVENTS]: events,
      [TITLE]: title
    } = diff;
    delete diff[REPLY];
    delete diff[EVENTS];
    delete diff[TITLE];
    return {
      diff,
      title,
      reply: reply || null,
      events: events || []
    };
  }

  constructor(viewId, rendered) {
    this.viewId = viewId;
    this.rendered = {};
    this.mergeDiff(rendered);
  }

  parentViewId() {
    return this.viewId;
  }

  toString(onlyCids) {
    return this.recursiveToString(this.rendered, this.rendered[COMPONENTS], onlyCids);
  }

  recursiveToString(rendered, components = rendered[COMPONENTS], onlyCids) {
    onlyCids = onlyCids ? new Set(onlyCids) : null;
    let output = {
      buffer: "",
      components,
      onlyCids
    };
    this.toOutputBuffer(rendered, output);
    return output.buffer;
  }

  componentCIDs(diff) {
    return Object.keys(diff[COMPONENTS] || {}).map(i => parseInt(i));
  }

  isComponentOnlyDiff(diff) {
    if (!diff[COMPONENTS]) {
      return false;
    }

    return Object.keys(diff).length === 1;
  }

  getComponent(diff, cid) {
    return diff[COMPONENTS][cid];
  }

  mergeDiff(diff) {
    let newc = diff[COMPONENTS];
    let cache = {};
    delete diff[COMPONENTS];
    this.rendered = this.mutableMerge(this.rendered, diff);
    this.rendered[COMPONENTS] = this.rendered[COMPONENTS] || {};

    if (newc) {
      let oldc = this.rendered[COMPONENTS];

      for (let cid in newc) {
        newc[cid] = this.cachedFindComponent(cid, newc[cid], oldc, newc, cache);
      }

      for (var key in newc) {
        oldc[key] = newc[key];
      }

      diff[COMPONENTS] = newc;
    }
  }

  cachedFindComponent(cid, cdiff, oldc, newc, cache) {
    if (cache[cid]) {
      return cache[cid];
    } else {
      let ndiff,
          stat,
          scid = cdiff[STATIC];

      if (isCid(scid)) {
        let tdiff;

        if (scid > 0) {
          tdiff = this.cachedFindComponent(scid, newc[scid], oldc, newc, cache);
        } else {
          tdiff = oldc[-scid];
        }

        stat = tdiff[STATIC];
        ndiff = this.cloneMerge(tdiff, cdiff);
        ndiff[STATIC] = stat;
      } else {
        ndiff = cdiff[STATIC] !== void 0 ? cdiff : this.cloneMerge(oldc[cid] || {}, cdiff);
      }

      cache[cid] = ndiff;
      return ndiff;
    }
  }

  mutableMerge(target, source) {
    if (source[STATIC] !== void 0) {
      return source;
    } else {
      this.doMutableMerge(target, source);
      return target;
    }
  }

  doMutableMerge(target, source) {
    for (let key in source) {
      let val = source[key];
      let targetVal = target[key];

      if (isObject(val) && val[STATIC] === void 0 && isObject(targetVal)) {
        this.doMutableMerge(targetVal, val);
      } else {
        target[key] = val;
      }
    }
  }

  cloneMerge(target, source) {
    let merged = { ...target,
      ...source
    };

    for (let key in merged) {
      let val = source[key];
      let targetVal = target[key];

      if (isObject(val) && val[STATIC] === void 0 && isObject(targetVal)) {
        merged[key] = this.cloneMerge(targetVal, val);
      }
    }

    return merged;
  }

  componentToString(cid) {
    return this.recursiveCIDToString(this.rendered[COMPONENTS], cid);
  }

  pruneCIDs(cids) {
    cids.forEach(cid => delete this.rendered[COMPONENTS][cid]);
  }

  get() {
    return this.rendered;
  }

  isNewFingerprint(diff = {}) {
    return !!diff[STATIC];
  }

  toOutputBuffer(rendered, output) {
    if (rendered[DYNAMICS]) {
      return this.comprehensionToBuffer(rendered, output);
    }

    let {
      [STATIC]: statics
    } = rendered;
    output.buffer += statics[0];

    for (let i = 1; i < statics.length; i++) {
      this.dynamicToBuffer(rendered[i - 1], output);
      output.buffer += statics[i];
    }
  }

  comprehensionToBuffer(rendered, output) {
    let {
      [DYNAMICS]: dynamics,
      [STATIC]: statics
    } = rendered;

    for (let d = 0; d < dynamics.length; d++) {
      let dynamic = dynamics[d];
      output.buffer += statics[0];

      for (let i = 1; i < statics.length; i++) {
        this.dynamicToBuffer(dynamic[i - 1], output);
        output.buffer += statics[i];
      }
    }
  }

  dynamicToBuffer(rendered, output) {
    if (typeof rendered === "number") {
      output.buffer += this.recursiveCIDToString(output.components, rendered, output.onlyCids);
    } else if (isObject(rendered)) {
      this.toOutputBuffer(rendered, output);
    } else {
      output.buffer += rendered;
    }
  }

  recursiveCIDToString(components, cid, onlyCids) {
    let component = components[cid] || logError(`no component for CID ${cid}`, components);
    let template = document.createElement("template");
    template.innerHTML = this.recursiveToString(component, components, onlyCids);
    let container = template.content;
    let skip = onlyCids && !onlyCids.has(cid);
    let [hasChildNodes, hasChildComponents] = Array.from(container.childNodes).reduce(([hasNodes, hasComponents], child, i) => {
      if (child.nodeType === Node.ELEMENT_NODE) {
        if (child.getAttribute(PHX_COMPONENT)) {
          return [hasNodes, true];
        }

        child.setAttribute(PHX_COMPONENT, cid);

        if (!child.id) {
          child.id = `${this.parentViewId()}-${cid}-${i}`;
        }

        if (skip) {
          child.setAttribute(PHX_SKIP, "");
          child.innerHTML = "";
        }

        return [true, hasComponents];
      } else {
        if (child.nodeValue.trim() !== "") {
          logError(`only HTML element tags are allowed at the root of components.

got: "${child.nodeValue.trim()}"

within:
`, template.innerHTML.trim());
          child.replaceWith(this.createSpan(child.nodeValue, cid));
          return [true, hasComponents];
        } else {
          child.remove();
          return [hasNodes, hasComponents];
        }
      }
    }, [false, false]);

    if (!hasChildNodes && !hasChildComponents) {
      logError("expected at least one HTML element tag inside a component, but the component is empty:\n", template.innerHTML.trim());
      return this.createSpan("", cid).outerHTML;
    } else if (!hasChildNodes && hasChildComponents) {
      logError("expected at least one HTML element tag directly inside a component, but only subcomponents were found. A component must render at least one HTML tag directly inside itself.", template.innerHTML.trim());
      return template.innerHTML;
    } else {
      return template.innerHTML;
    }
  }

  createSpan(text, cid) {
    let span = document.createElement("span");
    span.innerText = text;
    span.setAttribute(PHX_COMPONENT, cid);
    return span;
  }

}; // js/phoenix_live_view/view_hook.js

var viewHookID = 1;
var ViewHook = class {
  static makeID() {
    return viewHookID++;
  }

  static elementID(el) {
    return el.phxHookId;
  }

  constructor(view, el, callbacks) {
    this.__view = view;
    this.__liveSocket = view.liveSocket;
    this.__callbacks = callbacks;
    this.__listeners = new Set();
    this.__isDisconnected = false;
    this.el = el;
    this.el.phxHookId = this.constructor.makeID();

    for (let key in this.__callbacks) {
      this[key] = this.__callbacks[key];
    }
  }

  __mounted() {
    this.mounted && this.mounted();
  }

  __updated() {
    this.updated && this.updated();
  }

  __beforeUpdate() {
    this.beforeUpdate && this.beforeUpdate();
  }

  __destroyed() {
    this.destroyed && this.destroyed();
  }

  __reconnected() {
    if (this.__isDisconnected) {
      this.__isDisconnected = false;
      this.reconnected && this.reconnected();
    }
  }

  __disconnected() {
    this.__isDisconnected = true;
    this.disconnected && this.disconnected();
  }

  pushEvent(event, payload = {}, onReply = function () {}) {
    return this.__view.pushHookEvent(null, event, payload, onReply);
  }

  pushEventTo(phxTarget, event, payload = {}, onReply = function () {}) {
    return this.__view.withinTargets(phxTarget, (view, targetCtx) => {
      return view.pushHookEvent(targetCtx, event, payload, onReply);
    });
  }

  handleEvent(event, callback) {
    let callbackRef = (customEvent, bypass) => bypass ? event : callback(customEvent.detail);

    window.addEventListener(`phx:hook:${event}`, callbackRef);

    this.__listeners.add(callbackRef);

    return callbackRef;
  }

  removeHandleEvent(callbackRef) {
    let event = callbackRef(null, true);
    window.removeEventListener(`phx:hook:${event}`, callbackRef);

    this.__listeners.delete(callbackRef);
  }

  upload(name, files) {
    return this.__view.dispatchUploads(name, files);
  }

  uploadTo(phxTarget, name, files) {
    return this.__view.withinTargets(phxTarget, view => view.dispatchUploads(name, files));
  }

  __cleanup__() {
    this.__listeners.forEach(callbackRef => this.removeHandleEvent(callbackRef));
  }

}; // js/phoenix_live_view/view.js

var serializeForm = (form, meta = {}) => {
  let formData = new FormData(form);
  let toRemove = [];
  formData.forEach((val, key, _index) => {
    if (val instanceof File) {
      toRemove.push(key);
    }
  });
  toRemove.forEach(key => formData.delete(key));
  let params = new URLSearchParams();

  for (let [key, val] of formData.entries()) {
    params.append(key, val);
  }

  for (let metaKey in meta) {
    params.append(metaKey, meta[metaKey]);
  }

  return params.toString();
};

var View = class {
  constructor(el, liveSocket, parentView, flash) {
    this.liveSocket = liveSocket;
    this.flash = flash;
    this.parent = parentView;
    this.root = parentView ? parentView.root : this;
    this.el = el;
    this.id = this.el.id;
    this.ref = 0;
    this.childJoins = 0;
    this.loaderTimer = null;
    this.pendingDiffs = [];
    this.pruningCIDs = [];
    this.redirect = false;
    this.href = null;
    this.joinCount = this.parent ? this.parent.joinCount - 1 : 0;
    this.joinPending = true;
    this.destroyed = false;

    this.joinCallback = function () {};

    this.stopCallback = function () {};

    this.pendingJoinOps = this.parent ? null : [];
    this.viewHooks = {};
    this.uploaders = {};
    this.formSubmits = [];
    this.children = this.parent ? null : {};
    this.root.children[this.id] = {};
    this.channel = this.liveSocket.channel(`lv:${this.id}`, () => {
      return {
        redirect: this.redirect ? this.href : void 0,
        url: this.redirect ? void 0 : this.href || void 0,
        params: this.connectParams(),
        session: this.getSession(),
        static: this.getStatic(),
        flash: this.flash
      };
    });
    this.showLoader(this.liveSocket.loaderTimeout);
    this.bindChannel();
  }

  setHref(href) {
    this.href = href;
  }

  setRedirect(href) {
    this.redirect = true;
    this.href = href;
  }

  isMain() {
    return this.liveSocket.main === this;
  }

  connectParams() {
    let params = this.liveSocket.params(this.el);
    let manifest = dom_default.all(document, `[${this.binding(PHX_TRACK_STATIC)}]`).map(node => node.src || node.href).filter(url => typeof url === "string");

    if (manifest.length > 0) {
      params["_track_static"] = manifest;
    }

    params["_mounts"] = this.joinCount;
    return params;
  }

  isConnected() {
    return this.channel.canPush();
  }

  getSession() {
    return this.el.getAttribute(PHX_SESSION);
  }

  getStatic() {
    let val = this.el.getAttribute(PHX_STATIC);
    return val === "" ? null : val;
  }

  destroy(callback = function () {}) {
    this.destroyAllChildren();
    this.destroyed = true;
    delete this.root.children[this.id];

    if (this.parent) {
      delete this.root.children[this.parent.id][this.id];
    }

    clearTimeout(this.loaderTimer);

    let onFinished = () => {
      callback();

      for (let id in this.viewHooks) {
        this.destroyHook(this.viewHooks[id]);
      }
    };

    dom_default.markPhxChildDestroyed(this.el);
    this.log("destroyed", () => ["the child has been removed from the parent"]);
    this.channel.leave().receive("ok", onFinished).receive("error", onFinished).receive("timeout", onFinished);
  }

  setContainerClasses(...classes) {
    this.el.classList.remove(PHX_CONNECTED_CLASS, PHX_DISCONNECTED_CLASS, PHX_ERROR_CLASS);
    this.el.classList.add(...classes);
  }

  isLoading() {
    return this.el.classList.contains(PHX_DISCONNECTED_CLASS);
  }

  showLoader(timeout) {
    clearTimeout(this.loaderTimer);

    if (timeout) {
      this.loaderTimer = setTimeout(() => this.showLoader(), timeout);
    } else {
      for (let id in this.viewHooks) {
        this.viewHooks[id].__disconnected();
      }

      this.setContainerClasses(PHX_DISCONNECTED_CLASS);
    }
  }

  hideLoader() {
    clearTimeout(this.loaderTimer);
    this.setContainerClasses(PHX_CONNECTED_CLASS);
  }

  triggerReconnected() {
    for (let id in this.viewHooks) {
      this.viewHooks[id].__reconnected();
    }
  }

  log(kind, msgCallback) {
    this.liveSocket.log(this, kind, msgCallback);
  }

  withinTargets(phxTarget, callback) {
    if (phxTarget instanceof HTMLElement) {
      return this.liveSocket.owner(phxTarget, view => callback(view, phxTarget));
    }

    if (/^(0|[1-9]\d*)$/.test(phxTarget)) {
      let targets = dom_default.findComponentNodeList(this.el, phxTarget);

      if (targets.length === 0) {
        logError(`no component found matching phx-target of ${phxTarget}`);
      } else {
        callback(this, targets[0]);
      }
    } else {
      let targets = Array.from(document.querySelectorAll(phxTarget));

      if (targets.length === 0) {
        logError(`nothing found matching the phx-target selector "${phxTarget}"`);
      }

      targets.forEach(target => this.liveSocket.owner(target, view => callback(view, target)));
    }
  }

  applyDiff(type, rawDiff, callback) {
    this.log(type, () => ["", clone(rawDiff)]);
    let {
      diff,
      reply,
      events,
      title
    } = Rendered.extract(rawDiff);

    if (title) {
      dom_default.putTitle(title);
    }

    callback({
      diff,
      reply,
      events
    });
    return reply;
  }

  onJoin(resp) {
    let {
      rendered,
      container
    } = resp;

    if (container) {
      let [tag, attrs] = container;
      this.el = dom_default.replaceRootContainer(this.el, tag, attrs);
    }

    this.childJoins = 0;
    this.joinPending = true;
    this.flash = null;
    browser_default.dropLocal(this.liveSocket.localStorage, window.location.pathname, CONSECUTIVE_RELOADS);
    this.applyDiff("mount", rendered, ({
      diff,
      events
    }) => {
      this.rendered = new Rendered(this.id, diff);
      let html = this.renderContainer(null, "join");
      this.dropPendingRefs();
      let forms = this.formsForRecovery(html);
      this.joinCount++;

      if (forms.length > 0) {
        forms.forEach(([form, newForm, newCid], i) => {
          this.pushFormRecovery(form, newCid, resp2 => {
            if (i === forms.length - 1) {
              this.onJoinComplete(resp2, html, events);
            }
          });
        });
      } else {
        this.onJoinComplete(resp, html, events);
      }
    });
  }

  dropPendingRefs() {
    dom_default.all(this.el, `[${PHX_REF}]`, el => el.removeAttribute(PHX_REF));
  }

  onJoinComplete({
    live_patch
  }, html, events) {
    if (this.joinCount > 1 || this.parent && !this.parent.isJoinPending()) {
      return this.applyJoinPatch(live_patch, html, events);
    }

    let newChildren = dom_default.findPhxChildrenInFragment(html, this.id).filter(toEl => {
      let fromEl = toEl.id && this.el.querySelector(`[id="${toEl.id}"]`);
      let phxStatic = fromEl && fromEl.getAttribute(PHX_STATIC);

      if (phxStatic) {
        toEl.setAttribute(PHX_STATIC, phxStatic);
      }

      return this.joinChild(toEl);
    });

    if (newChildren.length === 0) {
      if (this.parent) {
        this.root.pendingJoinOps.push([this, () => this.applyJoinPatch(live_patch, html, events)]);
        this.parent.ackJoin(this);
      } else {
        this.onAllChildJoinsComplete();
        this.applyJoinPatch(live_patch, html, events);
      }
    } else {
      this.root.pendingJoinOps.push([this, () => this.applyJoinPatch(live_patch, html, events)]);
    }
  }

  attachTrueDocEl() {
    this.el = dom_default.byId(this.id);
    this.el.setAttribute(PHX_ROOT_ID, this.root.id);
  }

  dispatchEvents(events) {
    events.forEach(([event, payload]) => {
      window.dispatchEvent(new CustomEvent(`phx:hook:${event}`, {
        detail: payload
      }));
    });
  }

  applyJoinPatch(live_patch, html, events) {
    this.attachTrueDocEl();
    let patch = new DOMPatch(this, this.el, this.id, html, null);
    patch.markPrunableContentForRemoval();
    this.performPatch(patch, false);
    this.joinNewChildren();
    dom_default.all(this.el, `[${this.binding(PHX_HOOK)}], [data-phx-${PHX_HOOK}]`, hookEl => {
      let hook = this.addHook(hookEl);

      if (hook) {
        hook.__mounted();
      }
    });
    this.joinPending = false;
    this.dispatchEvents(events);
    this.applyPendingUpdates();

    if (live_patch) {
      let {
        kind,
        to
      } = live_patch;
      this.liveSocket.historyPatch(to, kind);
    }

    this.hideLoader();

    if (this.joinCount > 1) {
      this.triggerReconnected();
    }

    this.stopCallback();
  }

  triggerBeforeUpdateHook(fromEl, toEl) {
    this.liveSocket.triggerDOM("onBeforeElUpdated", [fromEl, toEl]);
    let hook = this.getHook(fromEl);
    let isIgnored = hook && dom_default.isIgnored(fromEl, this.binding(PHX_UPDATE));

    if (hook && !fromEl.isEqualNode(toEl) && !(isIgnored && isEqualObj(fromEl.dataset, toEl.dataset))) {
      hook.__beforeUpdate();

      return hook;
    }
  }

  performPatch(patch, pruneCids) {
    let destroyedCIDs = [];
    let phxChildrenAdded = false;
    let updatedHookIds = new Set();
    patch.after("added", el => {
      this.liveSocket.triggerDOM("onNodeAdded", [el]);
      let newHook = this.addHook(el);

      if (newHook) {
        newHook.__mounted();
      }
    });
    patch.after("phxChildAdded", _el => phxChildrenAdded = true);
    patch.before("updated", (fromEl, toEl) => {
      let hook = this.triggerBeforeUpdateHook(fromEl, toEl);

      if (hook) {
        updatedHookIds.add(fromEl.id);
      }
    });
    patch.after("updated", el => {
      if (updatedHookIds.has(el.id)) {
        this.getHook(el).__updated();
      }
    });
    patch.after("discarded", el => {
      let cid = this.componentID(el);

      if (isCid(cid) && destroyedCIDs.indexOf(cid) === -1) {
        destroyedCIDs.push(cid);
      }

      let hook = this.getHook(el);
      hook && this.destroyHook(hook);
    });
    patch.perform();

    if (pruneCids) {
      this.maybePushComponentsDestroyed(destroyedCIDs);
    }

    return phxChildrenAdded;
  }

  joinNewChildren() {
    dom_default.findPhxChildren(this.el, this.id).forEach(el => this.joinChild(el));
  }

  getChildById(id) {
    return this.root.children[this.id][id];
  }

  getDescendentByEl(el) {
    if (el.id === this.id) {
      return this;
    } else {
      return this.children[el.getAttribute(PHX_PARENT_ID)][el.id];
    }
  }

  destroyDescendent(id) {
    for (let parentId in this.root.children) {
      for (let childId in this.root.children[parentId]) {
        if (childId === id) {
          return this.root.children[parentId][childId].destroy();
        }
      }
    }
  }

  joinChild(el) {
    let child = this.getChildById(el.id);

    if (!child) {
      let view = new View(el, this.liveSocket, this);
      this.root.children[this.id][view.id] = view;
      view.join();
      this.childJoins++;
      return true;
    }
  }

  isJoinPending() {
    return this.joinPending;
  }

  ackJoin(_child) {
    this.childJoins--;

    if (this.childJoins === 0) {
      if (this.parent) {
        this.parent.ackJoin(this);
      } else {
        this.onAllChildJoinsComplete();
      }
    }
  }

  onAllChildJoinsComplete() {
    this.joinCallback();
    this.pendingJoinOps.forEach(([view, op]) => {
      if (!view.isDestroyed()) {
        op();
      }
    });
    this.pendingJoinOps = [];
  }

  update(diff, events) {
    if (this.isJoinPending() || this.liveSocket.hasPendingLink()) {
      return this.pendingDiffs.push({
        diff,
        events
      });
    }

    this.rendered.mergeDiff(diff);
    let phxChildrenAdded = false;

    if (this.rendered.isComponentOnlyDiff(diff)) {
      this.liveSocket.time("component patch complete", () => {
        let parentCids = dom_default.findParentCIDs(this.el, this.rendered.componentCIDs(diff));
        parentCids.forEach(parentCID => {
          if (this.componentPatch(this.rendered.getComponent(diff, parentCID), parentCID)) {
            phxChildrenAdded = true;
          }
        });
      });
    } else if (!isEmpty(diff)) {
      this.liveSocket.time("full patch complete", () => {
        let html = this.renderContainer(diff, "update");
        let patch = new DOMPatch(this, this.el, this.id, html, null);
        phxChildrenAdded = this.performPatch(patch, true);
      });
    }

    this.dispatchEvents(events);

    if (phxChildrenAdded) {
      this.joinNewChildren();
    }
  }

  renderContainer(diff, kind) {
    return this.liveSocket.time(`toString diff (${kind})`, () => {
      let tag = this.el.tagName;
      let cids = diff ? this.rendered.componentCIDs(diff).concat(this.pruningCIDs) : null;
      let html = this.rendered.toString(cids);
      return `<${tag}>${html}</${tag}>`;
    });
  }

  componentPatch(diff, cid) {
    if (isEmpty(diff)) return false;
    let html = this.rendered.componentToString(cid);
    let patch = new DOMPatch(this, this.el, this.id, html, cid);
    let childrenAdded = this.performPatch(patch, true);
    return childrenAdded;
  }

  getHook(el) {
    return this.viewHooks[ViewHook.elementID(el)];
  }

  addHook(el) {
    if (ViewHook.elementID(el) || !el.getAttribute) {
      return;
    }

    let hookName = el.getAttribute(`data-phx-${PHX_HOOK}`) || el.getAttribute(this.binding(PHX_HOOK));

    if (hookName && !this.ownsElement(el)) {
      return;
    }

    let callbacks = this.liveSocket.getHookCallbacks(hookName);

    if (callbacks) {
      if (!el.id) {
        logError(`no DOM ID for hook "${hookName}". Hooks require a unique ID on each element.`, el);
      }

      let hook = new ViewHook(this, el, callbacks);
      this.viewHooks[ViewHook.elementID(hook.el)] = hook;
      return hook;
    } else if (hookName !== null) {
      logError(`unknown hook found for "${hookName}"`, el);
    }
  }

  destroyHook(hook) {
    hook.__destroyed();

    hook.__cleanup__();

    delete this.viewHooks[ViewHook.elementID(hook.el)];
  }

  applyPendingUpdates() {
    this.pendingDiffs.forEach(({
      diff,
      events
    }) => this.update(diff, events));
    this.pendingDiffs = [];
  }

  onChannel(event, cb) {
    this.liveSocket.onChannel(this.channel, event, resp => {
      if (this.isJoinPending()) {
        this.root.pendingJoinOps.push([this, () => cb(resp)]);
      } else {
        cb(resp);
      }
    });
  }

  bindChannel() {
    this.liveSocket.onChannel(this.channel, "diff", rawDiff => {
      this.applyDiff("update", rawDiff, ({
        diff,
        events
      }) => this.update(diff, events));
    });
    this.onChannel("redirect", ({
      to,
      flash
    }) => this.onRedirect({
      to,
      flash
    }));
    this.onChannel("live_patch", redir => this.onLivePatch(redir));
    this.onChannel("live_redirect", redir => this.onLiveRedirect(redir));
    this.channel.onError(reason => this.onError(reason));
    this.channel.onClose(reason => this.onClose(reason));
  }

  destroyAllChildren() {
    for (let id in this.root.children[this.id]) {
      this.getChildById(id).destroy();
    }
  }

  onLiveRedirect(redir) {
    let {
      to,
      kind,
      flash
    } = redir;
    let url = this.expandURL(to);
    this.liveSocket.historyRedirect(url, kind, flash);
  }

  onLivePatch(redir) {
    let {
      to,
      kind
    } = redir;
    this.href = this.expandURL(to);
    this.liveSocket.historyPatch(to, kind);
  }

  expandURL(to) {
    return to.startsWith("/") ? `${window.location.protocol}//${window.location.host}${to}` : to;
  }

  onRedirect({
    to,
    flash
  }) {
    this.liveSocket.redirect(to, flash);
  }

  isDestroyed() {
    return this.destroyed;
  }

  join(callback) {
    if (!this.parent) {
      this.stopCallback = this.liveSocket.withPageLoading({
        to: this.href,
        kind: "initial"
      });
    }

    this.joinCallback = () => callback && callback(this.joinCount);

    this.liveSocket.wrapPush(this, {
      timeout: false
    }, () => {
      return this.channel.join().receive("ok", data => !this.isDestroyed() && this.onJoin(data)).receive("error", resp => !this.isDestroyed() && this.onJoinError(resp)).receive("timeout", () => !this.isDestroyed() && this.onJoinError({
        reason: "timeout"
      }));
    });
  }

  onJoinError(resp) {
    if (resp.reason === "unauthorized" || resp.reason === "stale") {
      this.log("error", () => ["unauthorized live_redirect. Falling back to page request", resp]);
      return this.onRedirect({
        to: this.href
      });
    }

    if (resp.redirect || resp.live_redirect) {
      this.joinPending = false;
      this.channel.leave();
    }

    if (resp.redirect) {
      return this.onRedirect(resp.redirect);
    }

    if (resp.live_redirect) {
      return this.onLiveRedirect(resp.live_redirect);
    }

    this.log("error", () => ["unable to join", resp]);
    return this.liveSocket.reloadWithJitter(this);
  }

  onClose(reason) {
    if (this.isDestroyed()) {
      return;
    }

    if (this.isJoinPending() && document.visibilityState !== "hidden" || this.liveSocket.hasPendingLink() && reason !== "leave") {
      return this.liveSocket.reloadWithJitter(this);
    }

    this.destroyAllChildren();
    this.liveSocket.dropActiveElement(this);

    if (document.activeElement) {
      document.activeElement.blur();
    }

    if (this.liveSocket.isUnloaded()) {
      this.showLoader(BEFORE_UNLOAD_LOADER_TIMEOUT);
    }
  }

  onError(reason) {
    this.onClose(reason);
    this.log("error", () => ["view crashed", reason]);

    if (!this.liveSocket.isUnloaded()) {
      this.displayError();
    }
  }

  displayError() {
    if (this.isMain()) {
      dom_default.dispatchEvent(window, "phx:page-loading-start", {
        to: this.href,
        kind: "error"
      });
    }

    this.showLoader();
    this.setContainerClasses(PHX_DISCONNECTED_CLASS, PHX_ERROR_CLASS);
  }

  pushWithReply(refGenerator, event, payload, onReply = function () {}) {
    if (!this.isConnected()) {
      return;
    }

    let [ref, [el]] = refGenerator ? refGenerator() : [null, []];

    let onLoadingDone = function () {};

    if (el && el.getAttribute(this.binding(PHX_PAGE_LOADING)) !== null) {
      onLoadingDone = this.liveSocket.withPageLoading({
        kind: "element",
        target: el
      });
    }

    if (typeof payload.cid !== "number") {
      delete payload.cid;
    }

    return this.liveSocket.wrapPush(this, {
      timeout: true
    }, () => {
      return this.channel.push(event, payload, PUSH_TIMEOUT).receive("ok", resp => {
        let hookReply = null;

        if (ref !== null) {
          this.undoRefs(ref);
        }

        if (resp.diff) {
          hookReply = this.applyDiff("update", resp.diff, ({
            diff,
            events
          }) => {
            this.update(diff, events);
          });
        }

        if (resp.redirect) {
          this.onRedirect(resp.redirect);
        }

        if (resp.live_patch) {
          this.onLivePatch(resp.live_patch);
        }

        if (resp.live_redirect) {
          this.onLiveRedirect(resp.live_redirect);
        }

        onLoadingDone();
        onReply(resp, hookReply);
      });
    });
  }

  undoRefs(ref) {
    dom_default.all(this.el, `[${PHX_REF}="${ref}"]`, el => {
      let disabledVal = el.getAttribute(PHX_DISABLED);
      el.removeAttribute(PHX_REF);

      if (el.getAttribute(PHX_READONLY) !== null) {
        el.readOnly = false;
        el.removeAttribute(PHX_READONLY);
      }

      if (disabledVal !== null) {
        el.disabled = disabledVal === "true" ? true : false;
        el.removeAttribute(PHX_DISABLED);
      }

      PHX_EVENT_CLASSES.forEach(className => dom_default.removeClass(el, className));
      let disableRestore = el.getAttribute(PHX_DISABLE_WITH_RESTORE);

      if (disableRestore !== null) {
        el.innerText = disableRestore;
        el.removeAttribute(PHX_DISABLE_WITH_RESTORE);
      }

      let toEl = dom_default.private(el, PHX_REF);

      if (toEl) {
        let hook = this.triggerBeforeUpdateHook(el, toEl);
        DOMPatch.patchEl(el, toEl, this.liveSocket.getActiveElement());

        if (hook) {
          hook.__updated();
        }

        dom_default.deletePrivate(el, PHX_REF);
      }
    });
  }

  putRef(elements, event) {
    let newRef = this.ref++;
    let disableWith = this.binding(PHX_DISABLE_WITH);
    elements.forEach(el => {
      el.classList.add(`phx-${event}-loading`);
      el.setAttribute(PHX_REF, newRef);
      let disableText = el.getAttribute(disableWith);

      if (disableText !== null) {
        if (!el.getAttribute(PHX_DISABLE_WITH_RESTORE)) {
          el.setAttribute(PHX_DISABLE_WITH_RESTORE, el.innerText);
        }

        el.innerText = disableText;
      }
    });
    return [newRef, elements];
  }

  componentID(el) {
    let cid = el.getAttribute && el.getAttribute(PHX_COMPONENT);
    return cid ? parseInt(cid) : null;
  }

  targetComponentID(target, targetCtx) {
    if (target.getAttribute(this.binding("target"))) {
      return this.closestComponentID(targetCtx);
    } else {
      return null;
    }
  }

  closestComponentID(targetCtx) {
    if (targetCtx) {
      return maybe(targetCtx.closest(`[${PHX_COMPONENT}]`), el => this.ownsElement(el) && this.componentID(el));
    } else {
      return null;
    }
  }

  pushHookEvent(targetCtx, event, payload, onReply) {
    if (!this.isConnected()) {
      this.log("hook", () => ["unable to push hook event. LiveView not connected", event, payload]);
      return false;
    }

    let [ref, els] = this.putRef([], "hook");
    this.pushWithReply(() => [ref, els], "event", {
      type: "hook",
      event,
      value: payload,
      cid: this.closestComponentID(targetCtx)
    }, (resp, reply) => onReply(reply, ref));
    return ref;
  }

  extractMeta(el, meta) {
    let prefix = this.binding("value-");

    for (let i = 0; i < el.attributes.length; i++) {
      let name = el.attributes[i].name;

      if (name.startsWith(prefix)) {
        meta[name.replace(prefix, "")] = el.getAttribute(name);
      }
    }

    if (el.value !== void 0) {
      meta.value = el.value;

      if (el.tagName === "INPUT" && CHECKABLE_INPUTS.indexOf(el.type) >= 0 && !el.checked) {
        delete meta.value;
      }
    }

    return meta;
  }

  pushEvent(type, el, targetCtx, phxEvent, meta) {
    this.pushWithReply(() => this.putRef([el], type), "event", {
      type,
      event: phxEvent,
      value: this.extractMeta(el, meta),
      cid: this.targetComponentID(el, targetCtx)
    });
  }

  pushKey(keyElement, targetCtx, kind, phxEvent, meta) {
    this.pushWithReply(() => this.putRef([keyElement], kind), "event", {
      type: kind,
      event: phxEvent,
      value: this.extractMeta(keyElement, meta),
      cid: this.targetComponentID(keyElement, targetCtx)
    });
  }

  pushFileProgress(fileEl, entryRef, progress, onReply = function () {}) {
    this.liveSocket.withinOwners(fileEl.form, (view, targetCtx) => {
      view.pushWithReply(null, "progress", {
        event: fileEl.getAttribute(view.binding(PHX_PROGRESS)),
        ref: fileEl.getAttribute(PHX_UPLOAD_REF),
        entry_ref: entryRef,
        progress,
        cid: view.targetComponentID(fileEl.form, targetCtx)
      }, onReply);
    });
  }

  pushInput(inputEl, targetCtx, forceCid, phxEvent, eventTarget, callback) {
    let uploads;
    let cid = isCid(forceCid) ? forceCid : this.targetComponentID(inputEl.form, targetCtx);

    let refGenerator = () => this.putRef([inputEl, inputEl.form], "change");

    let formData = serializeForm(inputEl.form, {
      _target: eventTarget.name
    });

    if (inputEl.files && inputEl.files.length > 0) {
      LiveUploader.trackFiles(inputEl, Array.from(inputEl.files));
    }

    uploads = LiveUploader.serializeUploads(inputEl);
    let event = {
      type: "form",
      event: phxEvent,
      value: formData,
      uploads,
      cid
    };
    this.pushWithReply(refGenerator, "event", event, resp => {
      dom_default.showError(inputEl, this.liveSocket.binding(PHX_FEEDBACK_FOR));

      if (dom_default.isUploadInput(inputEl) && inputEl.getAttribute("data-phx-auto-upload") !== null) {
        if (LiveUploader.filesAwaitingPreflight(inputEl).length > 0) {
          let [ref, _els] = refGenerator();
          this.uploadFiles(inputEl.form, targetCtx, ref, cid, _uploads => {
            callback && callback(resp);
            this.triggerAwaitingSubmit(inputEl.form);
          });
        }
      } else {
        callback && callback(resp);
      }
    });
  }

  triggerAwaitingSubmit(formEl) {
    let awaitingSubmit = this.getScheduledSubmit(formEl);

    if (awaitingSubmit) {
      let [_el, _ref, callback] = awaitingSubmit;
      this.cancelSubmit(formEl);
      callback();
    }
  }

  getScheduledSubmit(formEl) {
    return this.formSubmits.find(([el, _callback]) => el.isSameNode(formEl));
  }

  scheduleSubmit(formEl, ref, callback) {
    if (this.getScheduledSubmit(formEl)) {
      return true;
    }

    this.formSubmits.push([formEl, ref, callback]);
  }

  cancelSubmit(formEl) {
    this.formSubmits = this.formSubmits.filter(([el, ref, _callback]) => {
      if (el.isSameNode(formEl)) {
        this.undoRefs(ref);
        return false;
      } else {
        return true;
      }
    });
  }

  pushFormSubmit(formEl, targetCtx, phxEvent, onReply) {
    let filterIgnored = el => {
      let userIgnored = closestPhxBinding(el, `${this.binding(PHX_UPDATE)}=ignore`, el.form);
      return !(userIgnored || closestPhxBinding(el, "data-phx-update=ignore", el.form));
    };

    let filterDisables = el => {
      return el.hasAttribute(this.binding(PHX_DISABLE_WITH));
    };

    let filterButton = el => el.tagName == "BUTTON";

    let filterInput = el => ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);

    let refGenerator = () => {
      let formElements = Array.from(formEl.elements);
      let disables = formElements.filter(filterDisables);
      let buttons = formElements.filter(filterButton).filter(filterIgnored);
      let inputs = formElements.filter(filterInput).filter(filterIgnored);
      buttons.forEach(button => {
        button.setAttribute(PHX_DISABLED, button.disabled);
        button.disabled = true;
      });
      inputs.forEach(input => {
        input.setAttribute(PHX_READONLY, input.readOnly);
        input.readOnly = true;

        if (input.files) {
          input.setAttribute(PHX_DISABLED, input.disabled);
          input.disabled = true;
        }
      });
      formEl.setAttribute(this.binding(PHX_PAGE_LOADING), "");
      return this.putRef([formEl].concat(disables).concat(buttons).concat(inputs), "submit");
    };

    let cid = this.targetComponentID(formEl, targetCtx);

    if (LiveUploader.hasUploadsInProgress(formEl)) {
      let [ref, _els] = refGenerator();
      return this.scheduleSubmit(formEl, ref, () => this.pushFormSubmit(formEl, targetCtx, phxEvent, onReply));
    } else if (LiveUploader.inputsAwaitingPreflight(formEl).length > 0) {
      let [ref, els] = refGenerator();

      let proxyRefGen = () => [ref, els];

      this.uploadFiles(formEl, targetCtx, ref, cid, _uploads => {
        let formData = serializeForm(formEl, {});
        this.pushWithReply(proxyRefGen, "event", {
          type: "form",
          event: phxEvent,
          value: formData,
          cid
        }, onReply);
      });
    } else {
      let formData = serializeForm(formEl);
      this.pushWithReply(refGenerator, "event", {
        type: "form",
        event: phxEvent,
        value: formData,
        cid
      }, onReply);
    }
  }

  uploadFiles(formEl, targetCtx, ref, cid, onComplete) {
    let joinCountAtUpload = this.joinCount;
    let inputEls = LiveUploader.activeFileInputs(formEl);
    let numFileInputsInProgress = inputEls.length;
    inputEls.forEach(inputEl => {
      let uploader = new LiveUploader(inputEl, this, () => {
        numFileInputsInProgress--;

        if (numFileInputsInProgress === 0) {
          onComplete();
        }
      });
      this.uploaders[inputEl] = uploader;
      let entries = uploader.entries().map(entry => entry.toPreflightPayload());
      let payload = {
        ref: inputEl.getAttribute(PHX_UPLOAD_REF),
        entries,
        cid: this.targetComponentID(inputEl.form, targetCtx)
      };
      this.log("upload", () => ["sending preflight request", payload]);
      this.pushWithReply(null, "allow_upload", payload, resp => {
        this.log("upload", () => ["got preflight response", resp]);

        if (resp.error) {
          this.undoRefs(ref);
          let [entry_ref, reason] = resp.error;
          this.log("upload", () => [`error for entry ${entry_ref}`, reason]);
        } else {
          let onError = callback => {
            this.channel.onError(() => {
              if (this.joinCount === joinCountAtUpload) {
                callback();
              }
            });
          };

          uploader.initAdapterUpload(resp, onError, this.liveSocket);
        }
      });
    });
  }

  dispatchUploads(name, filesOrBlobs) {
    let inputs = dom_default.findUploadInputs(this.el).filter(el => el.name === name);

    if (inputs.length === 0) {
      logError(`no live file inputs found matching the name "${name}"`);
    } else if (inputs.length > 1) {
      logError(`duplicate live file inputs found matching the name "${name}"`);
    } else {
      dom_default.dispatchEvent(inputs[0], PHX_TRACK_UPLOADS, {
        files: filesOrBlobs
      });
    }
  }

  pushFormRecovery(form, newCid, callback) {
    this.liveSocket.withinOwners(form, (view, targetCtx) => {
      let input = form.elements[0];
      let phxEvent = form.getAttribute(this.binding(PHX_AUTO_RECOVER)) || form.getAttribute(this.binding("change"));
      view.pushInput(input, targetCtx, newCid, phxEvent, input, callback);
    });
  }

  pushLinkPatch(href, targetEl, callback) {
    let linkRef = this.liveSocket.setPendingLink(href);
    let refGen = targetEl ? () => this.putRef([targetEl], "click") : null;
    this.pushWithReply(refGen, "live_patch", {
      url: href
    }, resp => {
      if (resp.link_redirect) {
        this.liveSocket.replaceMain(href, null, callback, linkRef);
      } else {
        if (this.liveSocket.commitPendingLink(linkRef)) {
          this.href = href;
        }

        this.applyPendingUpdates();
        callback && callback(linkRef);
      }
    }).receive("timeout", () => this.liveSocket.redirect(window.location.href));
  }

  formsForRecovery(html) {
    if (this.joinCount === 0) {
      return [];
    }

    let phxChange = this.binding("change");
    let template = document.createElement("template");
    template.innerHTML = html;
    return dom_default.all(this.el, `form[${phxChange}]`).filter(form => form.id && this.ownsElement(form)).filter(form => form.elements.length > 0).filter(form => form.getAttribute(this.binding(PHX_AUTO_RECOVER)) !== "ignore").map(form => {
      let newForm = template.content.querySelector(`form[id="${form.id}"][${phxChange}="${form.getAttribute(phxChange)}"]`);

      if (newForm) {
        return [form, newForm, this.componentID(newForm)];
      } else {
        return [form, null, null];
      }
    }).filter(([form, newForm, newCid]) => newForm);
  }

  maybePushComponentsDestroyed(destroyedCIDs) {
    let willDestroyCIDs = destroyedCIDs.filter(cid => {
      return dom_default.findComponentNodeList(this.el, cid).length === 0;
    });

    if (willDestroyCIDs.length > 0) {
      this.pruningCIDs.push(...willDestroyCIDs);
      this.pushWithReply(null, "cids_will_destroy", {
        cids: willDestroyCIDs
      }, () => {
        this.pruningCIDs = this.pruningCIDs.filter(cid => willDestroyCIDs.indexOf(cid) !== -1);
        let completelyDestroyCIDs = willDestroyCIDs.filter(cid => {
          return dom_default.findComponentNodeList(this.el, cid).length === 0;
        });

        if (completelyDestroyCIDs.length > 0) {
          this.pushWithReply(null, "cids_destroyed", {
            cids: completelyDestroyCIDs
          }, resp => {
            this.rendered.pruneCIDs(resp.cids);
          });
        }
      });
    }
  }

  ownsElement(el) {
    return el.getAttribute(PHX_PARENT_ID) === this.id || maybe(el.closest(PHX_VIEW_SELECTOR), node => node.id) === this.id;
  }

  submitForm(form, targetCtx, phxEvent) {
    dom_default.putPrivate(form, PHX_HAS_SUBMITTED, true);
    this.liveSocket.blurActiveElement(this);
    this.pushFormSubmit(form, targetCtx, phxEvent, () => {
      this.liveSocket.restorePreviouslyActiveFocus();
    });
  }

  binding(kind) {
    return this.liveSocket.binding(kind);
  }

}; // js/phoenix_live_view/live_socket.js

var LiveSocket = class {
  constructor(url, phxSocket, opts = {}) {
    this.unloaded = false;

    if (!phxSocket || phxSocket.constructor.name === "Object") {
      throw new Error(`
      a phoenix Socket must be provided as the second argument to the LiveSocket constructor. For example:

          import {Socket} from "phoenix"
          import LiveSocket from "phoenix_live_view"
          let liveSocket = new LiveSocket("/live", Socket, {...})
      `);
    }

    this.socket = new phxSocket(url, opts);
    this.bindingPrefix = opts.bindingPrefix || BINDING_PREFIX;
    this.opts = opts;
    this.params = closure(opts.params || {});
    this.viewLogger = opts.viewLogger;
    this.metadataCallbacks = opts.metadata || {};
    this.defaults = Object.assign(clone(DEFAULTS), opts.defaults || {});
    this.activeElement = null;
    this.prevActive = null;
    this.silenced = false;
    this.main = null;
    this.linkRef = 1;
    this.roots = {};
    this.href = window.location.href;
    this.pendingLink = null;
    this.currentLocation = clone(window.location);
    this.hooks = opts.hooks || {};
    this.uploaders = opts.uploaders || {};
    this.loaderTimeout = opts.loaderTimeout || LOADER_TIMEOUT;
    this.localStorage = opts.localStorage || window.localStorage;
    this.sessionStorage = opts.sessionStorage || window.sessionStorage;
    this.boundTopLevelEvents = false;
    this.domCallbacks = Object.assign({
      onNodeAdded: closure(),
      onBeforeElUpdated: closure()
    }, opts.dom || {});
    window.addEventListener("pagehide", _e => {
      this.unloaded = true;
    });
    this.socket.onOpen(() => {
      if (this.isUnloaded()) {
        window.location.reload();
      }
    });
  }

  isProfileEnabled() {
    return this.sessionStorage.getItem(PHX_LV_PROFILE) === "true";
  }

  isDebugEnabled() {
    return this.sessionStorage.getItem(PHX_LV_DEBUG) === "true";
  }

  enableDebug() {
    this.sessionStorage.setItem(PHX_LV_DEBUG, "true");
  }

  enableProfiling() {
    this.sessionStorage.setItem(PHX_LV_PROFILE, "true");
  }

  disableDebug() {
    this.sessionStorage.removeItem(PHX_LV_DEBUG);
  }

  disableProfiling() {
    this.sessionStorage.removeItem(PHX_LV_PROFILE);
  }

  enableLatencySim(upperBoundMs) {
    this.enableDebug();
    console.log("latency simulator enabled for the duration of this browser session. Call disableLatencySim() to disable");
    this.sessionStorage.setItem(PHX_LV_LATENCY_SIM, upperBoundMs);
  }

  disableLatencySim() {
    this.sessionStorage.removeItem(PHX_LV_LATENCY_SIM);
  }

  getLatencySim() {
    let str = this.sessionStorage.getItem(PHX_LV_LATENCY_SIM);
    return str ? parseInt(str) : null;
  }

  getSocket() {
    return this.socket;
  }

  connect() {
    let doConnect = () => {
      if (this.joinRootViews()) {
        this.bindTopLevelEvents();
        this.socket.connect();
      }
    };

    if (["complete", "loaded", "interactive"].indexOf(document.readyState) >= 0) {
      doConnect();
    } else {
      document.addEventListener("DOMContentLoaded", () => doConnect());
    }
  }

  disconnect(callback) {
    this.socket.disconnect(callback);
  }

  triggerDOM(kind, args) {
    this.domCallbacks[kind](...args);
  }

  time(name, func) {
    if (!this.isProfileEnabled() || !console.time) {
      return func();
    }

    console.time(name);
    let result = func();
    console.timeEnd(name);
    return result;
  }

  log(view, kind, msgCallback) {
    if (this.viewLogger) {
      let [msg, obj] = msgCallback();
      this.viewLogger(view, kind, msg, obj);
    } else if (this.isDebugEnabled()) {
      let [msg, obj] = msgCallback();
      debug(view, kind, msg, obj);
    }
  }

  onChannel(channel, event, cb) {
    channel.on(event, data => {
      let latency = this.getLatencySim();

      if (!latency) {
        cb(data);
      } else {
        console.log(`simulating ${latency}ms of latency from server to client`);
        setTimeout(() => cb(data), latency);
      }
    });
  }

  wrapPush(view, opts, push) {
    let latency = this.getLatencySim();
    let oldJoinCount = view.joinCount;

    if (!latency) {
      if (opts.timeout) {
        return push().receive("timeout", () => {
          if (view.joinCount === oldJoinCount && !view.isDestroyed()) {
            this.reloadWithJitter(view, () => {
              this.log(view, "timeout", () => ["received timeout while communicating with server. Falling back to hard refresh for recovery"]);
            });
          }
        });
      } else {
        return push();
      }
    }

    console.log(`simulating ${latency}ms of latency from client to server`);
    let fakePush = {
      receives: [],

      receive(kind, cb) {
        this.receives.push([kind, cb]);
      }

    };
    setTimeout(() => {
      if (view.isDestroyed()) {
        return;
      }

      fakePush.receives.reduce((acc, [kind, cb]) => acc.receive(kind, cb), push());
    }, latency);
    return fakePush;
  }

  reloadWithJitter(view, log) {
    view.destroy();
    this.disconnect();
    let [minMs, maxMs] = RELOAD_JITTER;
    let afterMs = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
    let tries = browser_default.updateLocal(this.localStorage, window.location.pathname, CONSECUTIVE_RELOADS, 0, count => count + 1);
    log ? log() : this.log(view, "join", () => [`encountered ${tries} consecutive reloads`]);

    if (tries > MAX_RELOADS) {
      this.log(view, "join", () => [`exceeded ${MAX_RELOADS} consecutive reloads. Entering failsafe mode`]);
      afterMs = FAILSAFE_JITTER;
    }

    setTimeout(() => {
      if (this.hasPendingLink()) {
        window.location = this.pendingLink;
      } else {
        window.location.reload();
      }
    }, afterMs);
  }

  getHookCallbacks(name) {
    return name && name.startsWith("Phoenix.") ? hooks_default[name.split(".")[1]] : this.hooks[name];
  }

  isUnloaded() {
    return this.unloaded;
  }

  isConnected() {
    return this.socket.isConnected();
  }

  getBindingPrefix() {
    return this.bindingPrefix;
  }

  binding(kind) {
    return `${this.getBindingPrefix()}${kind}`;
  }

  channel(topic, params) {
    return this.socket.channel(topic, params);
  }

  joinRootViews() {
    let rootsFound = false;
    dom_default.all(document, `${PHX_VIEW_SELECTOR}:not([${PHX_PARENT_ID}])`, rootEl => {
      if (!this.getRootById(rootEl.id)) {
        let view = this.newRootView(rootEl);
        view.setHref(this.getHref());
        view.join();

        if (rootEl.getAttribute(PHX_MAIN)) {
          this.main = view;
        }
      }

      rootsFound = true;
    });
    return rootsFound;
  }

  redirect(to, flash) {
    this.disconnect();
    browser_default.redirect(to, flash);
  }

  replaceMain(href, flash, callback = null, linkRef = this.setPendingLink(href)) {
    let oldMainEl = this.main.el;
    let newMainEl = dom_default.cloneNode(oldMainEl, "");
    this.main.showLoader(this.loaderTimeout);
    this.main.destroy();
    this.main = this.newRootView(newMainEl, flash);
    this.main.setRedirect(href);
    this.main.join(joinCount => {
      if (joinCount === 1 && this.commitPendingLink(linkRef)) {
        oldMainEl.replaceWith(newMainEl);
        callback && callback();
      }
    });
  }

  isPhxView(el) {
    return el.getAttribute && el.getAttribute(PHX_SESSION) !== null;
  }

  newRootView(el, flash) {
    let view = new View(el, this, null, flash);
    this.roots[view.id] = view;
    return view;
  }

  owner(childEl, callback) {
    let view = maybe(childEl.closest(PHX_VIEW_SELECTOR), el => this.getViewByEl(el));

    if (view) {
      callback(view);
    }
  }

  withinOwners(childEl, callback) {
    this.owner(childEl, view => {
      let phxTarget = childEl.getAttribute(this.binding("target"));

      if (phxTarget === null) {
        callback(view, childEl);
      } else {
        view.withinTargets(phxTarget, callback);
      }
    });
  }

  getViewByEl(el) {
    let rootId = el.getAttribute(PHX_ROOT_ID);
    return maybe(this.getRootById(rootId), root => root.getDescendentByEl(el));
  }

  getRootById(id) {
    return this.roots[id];
  }

  destroyAllViews() {
    for (let id in this.roots) {
      this.roots[id].destroy();
      delete this.roots[id];
    }
  }

  destroyViewByEl(el) {
    let root = this.getRootById(el.getAttribute(PHX_ROOT_ID));

    if (root) {
      root.destroyDescendent(el.id);
    }
  }

  setActiveElement(target) {
    if (this.activeElement === target) {
      return;
    }

    this.activeElement = target;

    let cancel = () => {
      if (target === this.activeElement) {
        this.activeElement = null;
      }

      target.removeEventListener("mouseup", this);
      target.removeEventListener("touchend", this);
    };

    target.addEventListener("mouseup", cancel);
    target.addEventListener("touchend", cancel);
  }

  getActiveElement() {
    if (document.activeElement === document.body) {
      return this.activeElement || document.activeElement;
    } else {
      return document.activeElement || document.body;
    }
  }

  dropActiveElement(view) {
    if (this.prevActive && view.ownsElement(this.prevActive)) {
      this.prevActive = null;
    }
  }

  restorePreviouslyActiveFocus() {
    if (this.prevActive && this.prevActive !== document.body) {
      this.prevActive.focus();
    }
  }

  blurActiveElement() {
    this.prevActive = this.getActiveElement();

    if (this.prevActive !== document.body) {
      this.prevActive.blur();
    }
  }

  bindTopLevelEvents() {
    if (this.boundTopLevelEvents) {
      return;
    }

    this.boundTopLevelEvents = true;
    document.body.addEventListener("click", function () {});
    window.addEventListener("pageshow", e => {
      if (e.persisted) {
        this.getSocket().disconnect();
        this.withPageLoading({
          to: window.location.href,
          kind: "redirect"
        });
        window.location.reload();
      }
    }, true);
    this.bindNav();
    this.bindClicks();
    this.bindForms();
    this.bind({
      keyup: "keyup",
      keydown: "keydown"
    }, (e, type, view, target, targetCtx, phxEvent, _phxTarget) => {
      let matchKey = target.getAttribute(this.binding(PHX_KEY));
      let pressedKey = e.key && e.key.toLowerCase();

      if (matchKey && matchKey.toLowerCase() !== pressedKey) {
        return;
      }

      view.pushKey(target, targetCtx, type, phxEvent, {
        key: e.key,
        ...this.eventMeta(type, e, target)
      });
    });
    this.bind({
      blur: "focusout",
      focus: "focusin"
    }, (e, type, view, targetEl, targetCtx, phxEvent, phxTarget) => {
      if (!phxTarget) {
        view.pushEvent(type, targetEl, targetCtx, phxEvent, this.eventMeta(type, e, targetEl));
      }
    });
    this.bind({
      blur: "blur",
      focus: "focus"
    }, (e, type, view, targetEl, targetCtx, phxEvent, phxTarget) => {
      if (phxTarget && !phxTarget !== "window") {
        view.pushEvent(type, targetEl, targetCtx, phxEvent, this.eventMeta(type, e, targetEl));
      }
    });
    window.addEventListener("dragover", e => e.preventDefault());
    window.addEventListener("drop", e => {
      e.preventDefault();
      let dropTargetId = maybe(closestPhxBinding(e.target, this.binding(PHX_DROP_TARGET)), trueTarget => {
        return trueTarget.getAttribute(this.binding(PHX_DROP_TARGET));
      });
      let dropTarget = dropTargetId && document.getElementById(dropTargetId);
      let files = Array.from(e.dataTransfer.files || []);

      if (!dropTarget || dropTarget.disabled || files.length === 0 || !(dropTarget.files instanceof FileList)) {
        return;
      }

      LiveUploader.trackFiles(dropTarget, files);
      dropTarget.dispatchEvent(new Event("input", {
        bubbles: true
      }));
    });
    this.on(PHX_TRACK_UPLOADS, e => {
      let uploadTarget = e.target;

      if (!dom_default.isUploadInput(uploadTarget)) {
        return;
      }

      let files = Array.from(e.detail.files || []).filter(f => f instanceof File || f instanceof Blob);
      LiveUploader.trackFiles(uploadTarget, files);
      uploadTarget.dispatchEvent(new Event("input", {
        bubbles: true
      }));
    });
  }

  eventMeta(eventName, e, targetEl) {
    let callback = this.metadataCallbacks[eventName];
    return callback ? callback(e, targetEl) : {};
  }

  setPendingLink(href) {
    this.linkRef++;
    this.pendingLink = href;
    return this.linkRef;
  }

  commitPendingLink(linkRef) {
    if (this.linkRef !== linkRef) {
      return false;
    } else {
      this.href = this.pendingLink;
      this.pendingLink = null;
      return true;
    }
  }

  getHref() {
    return this.href;
  }

  hasPendingLink() {
    return !!this.pendingLink;
  }

  bind(events, callback) {
    for (let event in events) {
      let browserEventName = events[event];
      this.on(browserEventName, e => {
        let binding = this.binding(event);
        let windowBinding = this.binding(`window-${event}`);
        let targetPhxEvent = e.target.getAttribute && e.target.getAttribute(binding);

        if (targetPhxEvent) {
          this.debounce(e.target, e, () => {
            this.withinOwners(e.target, (view, targetCtx) => {
              callback(e, event, view, e.target, targetCtx, targetPhxEvent, null);
            });
          });
        } else {
          dom_default.all(document, `[${windowBinding}]`, el => {
            let phxEvent = el.getAttribute(windowBinding);
            this.debounce(el, e, () => {
              this.withinOwners(el, (view, targetCtx) => {
                callback(e, event, view, el, targetCtx, phxEvent, "window");
              });
            });
          });
        }
      });
    }
  }

  bindClicks() {
    this.bindClick("click", "click", false);
    this.bindClick("mousedown", "capture-click", true);
  }

  bindClick(eventName, bindingName, capture) {
    let click = this.binding(bindingName);
    window.addEventListener(eventName, e => {
      if (!this.isConnected()) {
        return;
      }

      let target = null;

      if (capture) {
        target = e.target.matches(`[${click}]`) ? e.target : e.target.querySelector(`[${click}]`);
      } else {
        target = closestPhxBinding(e.target, click);
      }

      let phxEvent = target && target.getAttribute(click);

      if (!phxEvent) {
        return;
      }

      if (target.getAttribute("href") === "#") {
        e.preventDefault();
      }

      this.debounce(target, e, () => {
        this.withinOwners(target, (view, targetCtx) => {
          view.pushEvent("click", target, targetCtx, phxEvent, this.eventMeta("click", e, target));
        });
      });
    }, capture);
  }

  bindNav() {
    if (!browser_default.canPushState()) {
      return;
    }

    if (history.scrollRestoration) {
      history.scrollRestoration = "manual";
    }

    let scrollTimer = null;
    window.addEventListener("scroll", _e => {
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => {
        browser_default.updateCurrentState(state => Object.assign(state, {
          scroll: window.scrollY
        }));
      }, 100);
    });
    window.addEventListener("popstate", event => {
      if (!this.registerNewLocation(window.location)) {
        return;
      }

      let {
        type,
        id,
        root,
        scroll
      } = event.state || {};
      let href = window.location.href;

      if (this.main.isConnected() && type === "patch" && id === this.main.id) {
        this.main.pushLinkPatch(href, null);
      } else {
        this.replaceMain(href, null, () => {
          if (root) {
            this.replaceRootHistory();
          }

          if (typeof scroll === "number") {
            setTimeout(() => {
              window.scrollTo(0, scroll);
            }, 0);
          }
        });
      }
    }, false);
    window.addEventListener("click", e => {
      let target = closestPhxBinding(e.target, PHX_LIVE_LINK);
      let type = target && target.getAttribute(PHX_LIVE_LINK);
      let wantsNewTab = e.metaKey || e.ctrlKey || e.button === 1;

      if (!type || !this.isConnected() || !this.main || wantsNewTab) {
        return;
      }

      let href = target.href;
      let linkState = target.getAttribute(PHX_LINK_STATE);
      e.preventDefault();

      if (this.pendingLink === href) {
        return;
      }

      if (type === "patch") {
        this.pushHistoryPatch(href, linkState, target);
      } else if (type === "redirect") {
        this.historyRedirect(href, linkState);
      } else {
        throw new Error(`expected ${PHX_LIVE_LINK} to be "patch" or "redirect", got: ${type}`);
      }
    }, false);
  }

  withPageLoading(info, callback) {
    dom_default.dispatchEvent(window, "phx:page-loading-start", info);

    let done = () => dom_default.dispatchEvent(window, "phx:page-loading-stop", info);

    return callback ? callback(done) : done;
  }

  pushHistoryPatch(href, linkState, targetEl) {
    this.withPageLoading({
      to: href,
      kind: "patch"
    }, done => {
      this.main.pushLinkPatch(href, targetEl, linkRef => {
        this.historyPatch(href, linkState, linkRef);
        done();
      });
    });
  }

  historyPatch(href, linkState, linkRef = this.setPendingLink(href)) {
    if (!this.commitPendingLink(linkRef)) {
      return;
    }

    browser_default.pushState(linkState, {
      type: "patch",
      id: this.main.id
    }, href);
    this.registerNewLocation(window.location);
  }

  historyRedirect(href, linkState, flash) {
    let scroll = window.scrollY;
    this.withPageLoading({
      to: href,
      kind: "redirect"
    }, done => {
      this.replaceMain(href, flash, () => {
        browser_default.pushState(linkState, {
          type: "redirect",
          id: this.main.id,
          scroll
        }, href);
        this.registerNewLocation(window.location);
        done();
      });
    });
  }

  replaceRootHistory() {
    browser_default.pushState("replace", {
      root: true,
      type: "patch",
      id: this.main.id
    });
  }

  registerNewLocation(newLocation) {
    let {
      pathname,
      search
    } = this.currentLocation;

    if (pathname + search === newLocation.pathname + newLocation.search) {
      return false;
    } else {
      this.currentLocation = clone(newLocation);
      return true;
    }
  }

  bindForms() {
    let iterations = 0;
    this.on("submit", e => {
      let phxEvent = e.target.getAttribute(this.binding("submit"));

      if (!phxEvent) {
        return;
      }

      e.preventDefault();
      e.target.disabled = true;
      this.withinOwners(e.target, (view, targetCtx) => view.submitForm(e.target, targetCtx, phxEvent));
    }, false);

    for (let type of ["change", "input"]) {
      this.on(type, e => {
        let input = e.target;
        let phxEvent = input.form && input.form.getAttribute(this.binding("change"));

        if (!phxEvent) {
          return;
        }

        if (input.type === "number" && input.validity && input.validity.badInput) {
          return;
        }

        let currentIterations = iterations;
        iterations++;
        let {
          at,
          type: lastType
        } = dom_default.private(input, "prev-iteration") || {};

        if (at === currentIterations - 1 && type !== lastType) {
          return;
        }

        dom_default.putPrivate(input, "prev-iteration", {
          at: currentIterations,
          type
        });
        this.debounce(input, e, () => {
          this.withinOwners(input.form, (view, targetCtx) => {
            dom_default.putPrivate(input, PHX_HAS_FOCUSED, true);

            if (!dom_default.isTextualInput(input)) {
              this.setActiveElement(input);
            }

            view.pushInput(input, targetCtx, null, phxEvent, e.target);
          });
        });
      }, false);
    }
  }

  debounce(el, event, callback) {
    let phxDebounce = this.binding(PHX_DEBOUNCE);
    let phxThrottle = this.binding(PHX_THROTTLE);
    let defaultDebounce = this.defaults.debounce.toString();
    let defaultThrottle = this.defaults.throttle.toString();
    dom_default.debounce(el, event, phxDebounce, defaultDebounce, phxThrottle, defaultThrottle, callback);
  }

  silenceEvents(callback) {
    this.silenced = true;
    callback();
    this.silenced = false;
  }

  on(event, callback) {
    window.addEventListener(event, e => {
      if (!this.silenced) {
        callback(e);
      }
    });
  }

};


/***/ }),

/***/ "./css/app.scss":
/*!**********************!*\
  !*** ./css/app.scss ***!
  \**********************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

// extracted by mini-css-extract-plugin

/***/ }),

/***/ "./js/app.js":
/*!*******************!*\
  !*** ./js/app.js ***!
  \*******************/
/*! no exports provided */
/***/ (function(module, __webpack_exports__, __webpack_require__) {

"use strict";
__webpack_require__.r(__webpack_exports__);
/* harmony import */ var _css_app_scss__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! ../css/app.scss */ "./css/app.scss");
/* harmony import */ var _css_app_scss__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(_css_app_scss__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var phoenix_html__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! phoenix_html */ "../deps/phoenix_html/priv/static/phoenix_html.js");
/* harmony import */ var phoenix_html__WEBPACK_IMPORTED_MODULE_1___default = /*#__PURE__*/__webpack_require__.n(phoenix_html__WEBPACK_IMPORTED_MODULE_1__);
/* harmony import */ var phoenix__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! phoenix */ "../deps/phoenix/priv/static/phoenix.js");
/* harmony import */ var phoenix__WEBPACK_IMPORTED_MODULE_2___default = /*#__PURE__*/__webpack_require__.n(phoenix__WEBPACK_IMPORTED_MODULE_2__);
/* harmony import */ var nprogress__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(/*! nprogress */ "./node_modules/nprogress/nprogress.js");
/* harmony import */ var nprogress__WEBPACK_IMPORTED_MODULE_3___default = /*#__PURE__*/__webpack_require__.n(nprogress__WEBPACK_IMPORTED_MODULE_3__);
/* harmony import */ var phoenix_live_view__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(/*! phoenix_live_view */ "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js");
// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
 // webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import deps with the dep name or local files with a relative path, for example:
//
//     import {Socket} from "phoenix"
//     import socket from "./socket"
//





var csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
var liveSocket = new phoenix_live_view__WEBPACK_IMPORTED_MODULE_4__["LiveSocket"]("/live", phoenix__WEBPACK_IMPORTED_MODULE_2__["Socket"], {
  params: {
    _csrf_token: csrfToken
  }
}); // Show progress bar on live navigation and form submits

window.addEventListener("phx:page-loading-start", function (info) {
  return nprogress__WEBPACK_IMPORTED_MODULE_3___default.a.start();
});
window.addEventListener("phx:page-loading-stop", function (info) {
  return nprogress__WEBPACK_IMPORTED_MODULE_3___default.a.done();
}); // connect if there are any LiveViews on the page

liveSocket.connect(); // expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()

window.liveSocket = liveSocket;

/***/ }),

/***/ "./node_modules/nprogress/nprogress.js":
/*!*********************************************!*\
  !*** ./node_modules/nprogress/nprogress.js ***!
  \*********************************************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

var __WEBPACK_AMD_DEFINE_FACTORY__, __WEBPACK_AMD_DEFINE_RESULT__;/* NProgress, (c) 2013, 2014 Rico Sta. Cruz - http://ricostacruz.com/nprogress
 * @license MIT */

;(function(root, factory) {

  if (true) {
    !(__WEBPACK_AMD_DEFINE_FACTORY__ = (factory),
				__WEBPACK_AMD_DEFINE_RESULT__ = (typeof __WEBPACK_AMD_DEFINE_FACTORY__ === 'function' ?
				(__WEBPACK_AMD_DEFINE_FACTORY__.call(exports, __webpack_require__, exports, module)) :
				__WEBPACK_AMD_DEFINE_FACTORY__),
				__WEBPACK_AMD_DEFINE_RESULT__ !== undefined && (module.exports = __WEBPACK_AMD_DEFINE_RESULT__));
  } else {}

})(this, function() {
  var NProgress = {};

  NProgress.version = '0.2.0';

  var Settings = NProgress.settings = {
    minimum: 0.08,
    easing: 'ease',
    positionUsing: '',
    speed: 200,
    trickle: true,
    trickleRate: 0.02,
    trickleSpeed: 800,
    showSpinner: true,
    barSelector: '[role="bar"]',
    spinnerSelector: '[role="spinner"]',
    parent: 'body',
    template: '<div class="bar" role="bar"><div class="peg"></div></div><div class="spinner" role="spinner"><div class="spinner-icon"></div></div>'
  };

  /**
   * Updates configuration.
   *
   *     NProgress.configure({
   *       minimum: 0.1
   *     });
   */
  NProgress.configure = function(options) {
    var key, value;
    for (key in options) {
      value = options[key];
      if (value !== undefined && options.hasOwnProperty(key)) Settings[key] = value;
    }

    return this;
  };

  /**
   * Last number.
   */

  NProgress.status = null;

  /**
   * Sets the progress bar status, where `n` is a number from `0.0` to `1.0`.
   *
   *     NProgress.set(0.4);
   *     NProgress.set(1.0);
   */

  NProgress.set = function(n) {
    var started = NProgress.isStarted();

    n = clamp(n, Settings.minimum, 1);
    NProgress.status = (n === 1 ? null : n);

    var progress = NProgress.render(!started),
        bar      = progress.querySelector(Settings.barSelector),
        speed    = Settings.speed,
        ease     = Settings.easing;

    progress.offsetWidth; /* Repaint */

    queue(function(next) {
      // Set positionUsing if it hasn't already been set
      if (Settings.positionUsing === '') Settings.positionUsing = NProgress.getPositioningCSS();

      // Add transition
      css(bar, barPositionCSS(n, speed, ease));

      if (n === 1) {
        // Fade out
        css(progress, { 
          transition: 'none', 
          opacity: 1 
        });
        progress.offsetWidth; /* Repaint */

        setTimeout(function() {
          css(progress, { 
            transition: 'all ' + speed + 'ms linear', 
            opacity: 0 
          });
          setTimeout(function() {
            NProgress.remove();
            next();
          }, speed);
        }, speed);
      } else {
        setTimeout(next, speed);
      }
    });

    return this;
  };

  NProgress.isStarted = function() {
    return typeof NProgress.status === 'number';
  };

  /**
   * Shows the progress bar.
   * This is the same as setting the status to 0%, except that it doesn't go backwards.
   *
   *     NProgress.start();
   *
   */
  NProgress.start = function() {
    if (!NProgress.status) NProgress.set(0);

    var work = function() {
      setTimeout(function() {
        if (!NProgress.status) return;
        NProgress.trickle();
        work();
      }, Settings.trickleSpeed);
    };

    if (Settings.trickle) work();

    return this;
  };

  /**
   * Hides the progress bar.
   * This is the *sort of* the same as setting the status to 100%, with the
   * difference being `done()` makes some placebo effect of some realistic motion.
   *
   *     NProgress.done();
   *
   * If `true` is passed, it will show the progress bar even if its hidden.
   *
   *     NProgress.done(true);
   */

  NProgress.done = function(force) {
    if (!force && !NProgress.status) return this;

    return NProgress.inc(0.3 + 0.5 * Math.random()).set(1);
  };

  /**
   * Increments by a random amount.
   */

  NProgress.inc = function(amount) {
    var n = NProgress.status;

    if (!n) {
      return NProgress.start();
    } else {
      if (typeof amount !== 'number') {
        amount = (1 - n) * clamp(Math.random() * n, 0.1, 0.95);
      }

      n = clamp(n + amount, 0, 0.994);
      return NProgress.set(n);
    }
  };

  NProgress.trickle = function() {
    return NProgress.inc(Math.random() * Settings.trickleRate);
  };

  /**
   * Waits for all supplied jQuery promises and
   * increases the progress as the promises resolve.
   *
   * @param $promise jQUery Promise
   */
  (function() {
    var initial = 0, current = 0;

    NProgress.promise = function($promise) {
      if (!$promise || $promise.state() === "resolved") {
        return this;
      }

      if (current === 0) {
        NProgress.start();
      }

      initial++;
      current++;

      $promise.always(function() {
        current--;
        if (current === 0) {
            initial = 0;
            NProgress.done();
        } else {
            NProgress.set((initial - current) / initial);
        }
      });

      return this;
    };

  })();

  /**
   * (Internal) renders the progress bar markup based on the `template`
   * setting.
   */

  NProgress.render = function(fromStart) {
    if (NProgress.isRendered()) return document.getElementById('nprogress');

    addClass(document.documentElement, 'nprogress-busy');
    
    var progress = document.createElement('div');
    progress.id = 'nprogress';
    progress.innerHTML = Settings.template;

    var bar      = progress.querySelector(Settings.barSelector),
        perc     = fromStart ? '-100' : toBarPerc(NProgress.status || 0),
        parent   = document.querySelector(Settings.parent),
        spinner;
    
    css(bar, {
      transition: 'all 0 linear',
      transform: 'translate3d(' + perc + '%,0,0)'
    });

    if (!Settings.showSpinner) {
      spinner = progress.querySelector(Settings.spinnerSelector);
      spinner && removeElement(spinner);
    }

    if (parent != document.body) {
      addClass(parent, 'nprogress-custom-parent');
    }

    parent.appendChild(progress);
    return progress;
  };

  /**
   * Removes the element. Opposite of render().
   */

  NProgress.remove = function() {
    removeClass(document.documentElement, 'nprogress-busy');
    removeClass(document.querySelector(Settings.parent), 'nprogress-custom-parent');
    var progress = document.getElementById('nprogress');
    progress && removeElement(progress);
  };

  /**
   * Checks if the progress bar is rendered.
   */

  NProgress.isRendered = function() {
    return !!document.getElementById('nprogress');
  };

  /**
   * Determine which positioning CSS rule to use.
   */

  NProgress.getPositioningCSS = function() {
    // Sniff on document.body.style
    var bodyStyle = document.body.style;

    // Sniff prefixes
    var vendorPrefix = ('WebkitTransform' in bodyStyle) ? 'Webkit' :
                       ('MozTransform' in bodyStyle) ? 'Moz' :
                       ('msTransform' in bodyStyle) ? 'ms' :
                       ('OTransform' in bodyStyle) ? 'O' : '';

    if (vendorPrefix + 'Perspective' in bodyStyle) {
      // Modern browsers with 3D support, e.g. Webkit, IE10
      return 'translate3d';
    } else if (vendorPrefix + 'Transform' in bodyStyle) {
      // Browsers without 3D support, e.g. IE9
      return 'translate';
    } else {
      // Browsers without translate() support, e.g. IE7-8
      return 'margin';
    }
  };

  /**
   * Helpers
   */

  function clamp(n, min, max) {
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  /**
   * (Internal) converts a percentage (`0..1`) to a bar translateX
   * percentage (`-100%..0%`).
   */

  function toBarPerc(n) {
    return (-1 + n) * 100;
  }


  /**
   * (Internal) returns the correct CSS for changing the bar's
   * position given an n percentage, and speed and ease from Settings
   */

  function barPositionCSS(n, speed, ease) {
    var barCSS;

    if (Settings.positionUsing === 'translate3d') {
      barCSS = { transform: 'translate3d('+toBarPerc(n)+'%,0,0)' };
    } else if (Settings.positionUsing === 'translate') {
      barCSS = { transform: 'translate('+toBarPerc(n)+'%,0)' };
    } else {
      barCSS = { 'margin-left': toBarPerc(n)+'%' };
    }

    barCSS.transition = 'all '+speed+'ms '+ease;

    return barCSS;
  }

  /**
   * (Internal) Queues a function to be executed.
   */

  var queue = (function() {
    var pending = [];
    
    function next() {
      var fn = pending.shift();
      if (fn) {
        fn(next);
      }
    }

    return function(fn) {
      pending.push(fn);
      if (pending.length == 1) next();
    };
  })();

  /**
   * (Internal) Applies css properties to an element, similar to the jQuery 
   * css method.
   *
   * While this helper does assist with vendor prefixed property names, it 
   * does not perform any manipulation of values prior to setting styles.
   */

  var css = (function() {
    var cssPrefixes = [ 'Webkit', 'O', 'Moz', 'ms' ],
        cssProps    = {};

    function camelCase(string) {
      return string.replace(/^-ms-/, 'ms-').replace(/-([\da-z])/gi, function(match, letter) {
        return letter.toUpperCase();
      });
    }

    function getVendorProp(name) {
      var style = document.body.style;
      if (name in style) return name;

      var i = cssPrefixes.length,
          capName = name.charAt(0).toUpperCase() + name.slice(1),
          vendorName;
      while (i--) {
        vendorName = cssPrefixes[i] + capName;
        if (vendorName in style) return vendorName;
      }

      return name;
    }

    function getStyleProp(name) {
      name = camelCase(name);
      return cssProps[name] || (cssProps[name] = getVendorProp(name));
    }

    function applyCss(element, prop, value) {
      prop = getStyleProp(prop);
      element.style[prop] = value;
    }

    return function(element, properties) {
      var args = arguments,
          prop, 
          value;

      if (args.length == 2) {
        for (prop in properties) {
          value = properties[prop];
          if (value !== undefined && properties.hasOwnProperty(prop)) applyCss(element, prop, value);
        }
      } else {
        applyCss(element, args[1], args[2]);
      }
    }
  })();

  /**
   * (Internal) Determines if an element or space separated list of class names contains a class name.
   */

  function hasClass(element, name) {
    var list = typeof element == 'string' ? element : classList(element);
    return list.indexOf(' ' + name + ' ') >= 0;
  }

  /**
   * (Internal) Adds a class to an element.
   */

  function addClass(element, name) {
    var oldList = classList(element),
        newList = oldList + name;

    if (hasClass(oldList, name)) return; 

    // Trim the opening space.
    element.className = newList.substring(1);
  }

  /**
   * (Internal) Removes a class from an element.
   */

  function removeClass(element, name) {
    var oldList = classList(element),
        newList;

    if (!hasClass(element, name)) return;

    // Replace the class name.
    newList = oldList.replace(' ' + name + ' ', ' ');

    // Trim the opening and closing spaces.
    element.className = newList.substring(1, newList.length - 1);
  }

  /**
   * (Internal) Gets a space separated list of the class names on the element. 
   * The list is wrapped with a single space on each end to facilitate finding 
   * matches within the list.
   */

  function classList(element) {
    return (' ' + (element.className || '') + ' ').replace(/\s+/gi, ' ');
  }

  /**
   * (Internal) Removes an element from the DOM.
   */

  function removeElement(element) {
    element && element.parentNode && element.parentNode.removeChild(element);
  }

  return NProgress;
});



/***/ }),

/***/ 0:
/*!*************************!*\
  !*** multi ./js/app.js ***!
  \*************************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

module.exports = __webpack_require__(/*! ./js/app.js */"./js/app.js");


/***/ })

/******/ });
//# sourceMappingURL=app.js.map