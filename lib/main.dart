import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image/image.dart' as img;
import 'package:processing_camera_image/processing_camera_image.dart' as pc;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: CameraStream(camera: firstCamera),
    ),
  );
}

class CameraStream extends StatefulWidget {
  final CameraDescription camera;

  const CameraStream({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraStreamState createState() => _CameraStreamState();
}

class _CameraStreamState extends State<CameraStream> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isBlackScreen = false;
  bool _showMessage = false; // 메시지를 표시할지 여부를 제어하는 변수
  final TextEditingController _portController = TextEditingController(text: '8765');
  final TextEditingController _ipController = TextEditingController(text: '10.0.2.2');
  final TextEditingController _nameController = TextEditingController(text: 'Android Test');
  Timer? _messageTimer; // 메시지를 숨기기 위한 타이머
  int _jpegQuality = 80; // JPEG 압축률

  late pc.ProcessingCameraImage _processingCameraImage;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.ultraHigh,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initializeControllerFuture = _controller.initialize();
    _processingCameraImage = pc.ProcessingCameraImage();
    startStreaming();
  }

  @override
  void dispose() {
    _controller.dispose();
    _channel?.sink.close();
    _portController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectToWebSocket(String port, String ip, String name) async {
    if (_isConnected) {
      return;
    }

    final wsUrl = 'ws://$ip:$port/$name';
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel!.stream.listen((message) {
      print('Received message: $message');
    }, onDone: () {
      _disconnectFromWebSocket();
    }, onError: (error) {
      print('WebSocket error: $error');
      _disconnectFromWebSocket();
    });

    setState(() {
      _isConnected = true;
    });
    print('WebSocket connected to $wsUrl');
  }

  Future<void> _disconnectFromWebSocket() async {
    if (!_isConnected) {
      return;
    }

    setState(() {
      _isConnected = false;
    });
    _channel?.sink.close();
    print('WebSocket disconnected');
  }

  Future<void> startStreaming() async {
    await _initializeControllerFuture;

    _controller.startImageStream((CameraImage image) async {
      if (_channel == null || !_isConnected) {
        return;
      }

      final jpgFrame = await _convertYUV420ToJPG(image, quality: _jpegQuality);
      _channel!.sink.add(jpgFrame);
    });
  }

  Future<void> stopStreaming() async {
    await _controller.stopImageStream();
  }

  Future<Uint8List> _convertYUV420ToJPG(CameraImage image, {int quality = 75}) async {
    final img.Image? rgbImage = await _processingCameraImage.processCameraImageToRGB(
      width: image.width,
      height: image.height,
      plane0: image.planes[0].bytes,
      plane1: image.planes[1].bytes,
      plane2: image.planes[2].bytes,
      bytesPerRowPlane0: image.planes[0].bytesPerRow,
      bytesPerRowPlane1: image.planes[1].bytesPerRow,
      bytesPerPixelPlan1: image.planes[1].bytesPerPixel,
    );

    if (rgbImage == null) {
      throw Exception('Error converting image to RGB');
    }

    return Uint8List.fromList(img.encodeJpg(rgbImage, quality: quality));
  }

  void _toggleBlackScreen() {
    setState(() {
      _isBlackScreen = !_isBlackScreen;
      if (_isBlackScreen) {
        _showMessage = true;
        _messageTimer = Timer(Duration(seconds: 5), () {
          setState(() {
            _showMessage = false;
          });
        });
      } else {
        _messageTimer?.cancel();
        _showMessage = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onDoubleTap: () {
          if (_isBlackScreen) {
            _toggleBlackScreen(); // 검정색 화면을 해제
          }
        },
        child: Stack(
          children: [
            // 검정색 화면을 전면에 표시
            if (_isBlackScreen) ...[
              Container(
                color: Colors.black,
                child: Center(
                  child: _showMessage
                      ? Text(
                    'Double-tap to show UI',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  )
                      : SizedBox.shrink(),
                ),
              ),
            ],
            // UI 요소들을 전면에 배치
            AnimatedOpacity(
              opacity: _isBlackScreen ? 0.0 : 1.0,
              duration: Duration(milliseconds: 300),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _ipController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'IP',
                        hintText: 'Enter IP Address',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Port',
                        hintText: 'Enter port number',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Name',
                        hintText: 'Enter Camera Name',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      final port = _portController.text;
                      final ip = _ipController.text;
                      final name = _nameController.text;
                      if (_isConnected) {
                        await _disconnectFromWebSocket();
                      } else {
                        await _connectToWebSocket(port, ip, name);
                      }
                    },
                    child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _toggleBlackScreen,
                    child: Text(_isBlackScreen ? 'Show UI' : 'Show Black Screen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
