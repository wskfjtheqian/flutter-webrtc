import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as jsutil;

import 'package:flutter/services.dart';

import '../interface/media_stream.dart';
import '../interface/rtc_video_renderer.dart';
import 'media_stream_impl.dart';
import 'ui_fake.dart' if (dart.library.html) 'dart:ui' as ui;

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = {
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = {
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage = 'No further diagnostic information can be determined or provided.';

class RTCVideoRendererWeb extends VideoRenderer {
  html.VideoElement _audioElement;

  RTCVideoRendererWeb() : _textureId = _textureCounter++;

  static int _textureCounter = 1;

  final int _textureId;

  MediaStreamWeb _videoStream;

  MediaStreamWeb _audioStream;

  MediaStream _srcObject;

  final _subscriptions = <StreamSubscription>[];

  set objectFit(String fit) => findHtmlView()?.style?.objectFit = fit;

  set mirror(bool mirror) => findHtmlView()?.style?.transform = 'rotateY(${mirror ? "180" : "0"}deg)';

  @override
  int get videoWidth => value.width.toInt();

  @override
  int get videoHeight => value.height.toInt();

  @override
  int get textureId => _textureId;

  @override
  bool get muted => findHtmlView()?.muted ?? true;

  @override
  set muted(bool mute) => findHtmlView()?.muted = mute;

  @override
  bool get renderVideo => _srcObject != null;

  void _updateAllValues() {
    var element = findHtmlView();
    value = value.copyWith(
      rotation: 0,
      width: element?.videoWidth?.toDouble() ?? 0.0,
      height: element?.videoHeight?.toDouble() ?? 0.0,
      renderVideo: renderVideo,
    );
  }

  @override
  MediaStream get srcObject => _srcObject;

  @override
  set srcObject(MediaStream stream) {
    _srcObject = stream;

    if (null != stream) {
      if (stream.getVideoTracks().isNotEmpty) {
        _videoStream = MediaStreamWeb(html.MediaStream(), stream.ownerTag);
        stream.getVideoTracks().forEach((element) {
          _videoStream.addTrack(element);
        });
      }
      if (stream.getAudioTracks().isNotEmpty) {
        _audioStream = MediaStreamWeb(html.MediaStream(), stream.ownerTag);
        stream.getVideoTracks().forEach((element) {
          _audioStream.addTrack(element);
        });
      }
    } else {
      _videoStream = null;
      _audioStream = null;
    }

    if (null != _audioStream) {
      if (null == _audioElement) {
        _audioElement = html.VideoElement()
          ..id = 'audio_RTCVideoRenderer-$textureId'
          ..autoplay = true
          ..muted = _audioStream.ownerTag == 'local';
        getAudioManageDiv().append(_audioElement);
      }
      _audioElement?.srcObject = _audioStream?.jsStream;
    }
    findHtmlView()?.srcObject = _videoStream?.jsStream;

    value = value.copyWith(renderVideo: renderVideo);
  }

  html.DivElement getAudioManageDiv() {
    var div = html.document.getElementById('html_webrtc_audio_manage_list');
    if (null != div) {
      return div;
    }
    div = html.DivElement();
    div.id = 'html_webrtc_audio_manage_list';
    div.style.display = 'none';
    html.document.body.append(div);
    return div;
  }

  html.VideoElement findHtmlView() {
    final fltPv = html.document.getElementsByTagName('flt-platform-view');
    if (fltPv.isEmpty) return null;
    var child = (fltPv.first as html.Element).shadowRoot.childNodes;
    for (var item in child) {
      if ((item as html.Element).id == "video_RTCVideoRenderer-$textureId") {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    await _srcObject?.dispose();
    _srcObject = null;
    _subscriptions.forEach((s) => s.cancel());
    var element = findHtmlView();
    element?.removeAttribute('src');
    element?.load();
    getAudioManageDiv()?.remove();
    return super.dispose();
  }

  @override
  Future<bool> audioOutput(String deviceId) async {
    try {
      var element = findHtmlView();
      if (null != element && jsutil.hasProperty(element, 'setSinkId')) {
        await jsutil.promiseToFuture<void>(jsutil.callMethod(element, 'setSinkId', [deviceId]));

        return true;
      }
    } catch (e) {
      print('Unable to setSinkId: ${e.toString()}');
    }
    return false;
  }

  @override
  Future<void> initialize() async {
    var id = 'RTCVideoRenderer-$textureId';
    // // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(id, (int viewId) {
      _subscriptions.forEach((s) => s.cancel());
      _subscriptions.clear();

      var element = html.VideoElement()
        ..autoplay = true
        ..muted = false
        ..controls = false
        ..style.objectFit = 'contain'
        ..style.border = 'none'
        ..srcObject = _videoStream.jsStream
        ..id = "video_$id"
        ..setAttribute('playsinline', 'true');

      _subscriptions.add(
        element.onCanPlay.listen((dynamic _) {
          _updateAllValues();
          //print('RTCVideoRenderer: videoElement.onCanPlay ${value.toString()}');
        }),
      );

      _subscriptions.add(
        element.onResize.listen((dynamic _) {
          _updateAllValues();
          onResize?.call();
          //print('RTCVideoRenderer: videoElement.onResize ${value.toString()}');
        }),
      );

      // The error event fires when some form of error occurs while attempting to load or perform the media.
      _subscriptions.add(
        element.onError.listen((html.Event _) {
          // The Event itself (_) doesn't contain info about the actual error.
          // We need to look at the HTMLMediaElement.error.
          // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
          var error = element.error;
          print('RTCVideoRenderer: videoElement.onError, ${error.toString()}');
          throw PlatformException(
            code: _kErrorValueToErrorName[error.code],
            message: error.message != '' ? error.message : _kDefaultErrorMessage,
            details: _kErrorValueToErrorDescription[error.code],
          );
        }),
      );

      _subscriptions.add(
        element.onEnded.listen((dynamic _) {
          //print('RTCVideoRenderer: videoElement.onEnded');
        }),
      );

      return element;
    });
  }
}
