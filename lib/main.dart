import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(MaterialApp(home: DiceApp()));
}

class DiceApp extends StatefulWidget {
  @override
  _DiceAppState createState() => _DiceAppState();
}

class _DiceAppState extends State<DiceApp> with TickerProviderStateMixin {
  late List<Dice> dices;
  final Random random = Random();
  late AudioPlayer _audioPlayer;
  List<String> savedSets = [];
  FocusNode _focusNode = FocusNode();
  bool showSum = false;

  @override
  void initState() {
    super.initState();
    dices = [
      Dice(
        controller: AnimationController(
          duration: const Duration(milliseconds: 500),
          vsync: this,
        ),
      )
    ];
    loadDices();
    loadSavedSets();
    _audioPlayer = AudioPlayer();
    _loadAudio();
    _focusNode.requestFocus();
  }

  Future<void> _loadAudio() async {
    await _audioPlayer.setAsset('assets/dice_roll.mp3');
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _focusNode.dispose();
    for (var dice in dices) {
      dice.controller.dispose();
    }
    super.dispose();
  }

  void loadDices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt('diceCount') ?? 1;
    List<int> maxValues = prefs.getStringList('diceMaxValues')?.map(int.parse).toList() ?? [6];

    setState(() {
      dices = List.generate(count, (index) => Dice(
        maxValue: maxValues[index],
        color: getRandomColor(),
        controller: AnimationController(
          duration: const Duration(milliseconds: 500),
          vsync: this,
        ),
      ));
    });
  }

  void saveDices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('diceCount', dices.length);
    await prefs.setStringList('diceMaxValues', dices.map((d) => d.maxValue.toString()).toList());
  }

  void loadSavedSets() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      savedSets = prefs.getStringList('savedSets') ?? [];
    });
  }

  void addDice() {
    if (dices.length < 8) {
      setState(() {
        dices.add(Dice(
          color: getRandomColor(),
          controller: AnimationController(
            duration: const Duration(milliseconds: 500),
            vsync: this,
          ),
        ));
      });
      saveDices();
    }
  }

  void removeDice() {
    if (dices.length > 1) {
      setState(() {
        dices.last.controller.dispose();
        dices.removeLast();
      });
      saveDices();
    }
  }

  Future<void> rollDice(Dice dice) async {
    dice.controller.reset();
    dice.controller.forward();

    await _audioPlayer.stop();
    await _audioPlayer.seek(Duration.zero);
    _audioPlayer.play();  // await 제거

    for (int i = 0; i < 10; i++) {
      dice.tempValue = random.nextInt(dice.maxValue) + 1;
      setState(() {});  // 각 변경마다 setState 호출
      await Future.delayed(Duration(milliseconds: 50));
    }

    setState(() {
      dice.roll();
    });
  }

  Future<void> rollAllDices() async {
    List<Future> rollFutures = dices.map((dice) => rollDice(dice)).toList();
    await Future.wait(rollFutures);
  }

  Color getRandomColor() {
    return Color.fromARGB(
      255,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
  }

  int calculateSum() {
    return dices.fold(0, (sum, dice) => sum + dice.value);
  }

  Future<void> saveCurrentSet() async {
    String? setName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String name = '';
        return AlertDialog(
          title: Text('Set 이름 입력'),
          content: TextField(
            onChanged: (value) {
              name = value;
            },
            decoration: InputDecoration(hintText: "Set 이름을 입력하세요"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('취소'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('저장'),
              onPressed: () {
                Navigator.of(context).pop(name);
              },
            ),
          ],
        );
      },
    );

    if (setName != null && setName.isNotEmpty) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> sets = prefs.getStringList('savedSets') ?? [];

      if (sets.length >= 5) {
        int? overwriteIndex = await showDialog<int>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('저장 슬롯 선택'),
              content: Text('5개의 슬롯이 모두 찼습니다. 어느 슬롯을 덮어쓰시겠습니까?'),
              actions: List.generate(5, (index) {
                Map<String, dynamic> set = jsonDecode(sets[index]);
                return TextButton(
                  child: Text('${index + 1}. ${set['name']}'),
                  onPressed: () {
                    Navigator.of(context).pop(index);
                  },
                );
              }),
            );
          },
        );

        if (overwriteIndex != null) {
          sets[overwriteIndex] = jsonEncode({
            'name': setName,
            'dices': dices.map((d) => {'maxValue': d.maxValue, 'color': d.color.value}).toList(),
          });
        } else {
          return; // 사용자가 취소한 경우
        }
      } else {
        sets.add(jsonEncode({
          'name': setName,
          'dices': dices.map((d) => {'maxValue': d.maxValue, 'color': d.color.value}).toList(),
        }));
      }

      await prefs.setStringList('savedSets', sets);

      setState(() {
        savedSets = sets;
      });
    }
  }

  void loadSet(String setJson) {
    Map<String, dynamic> set = jsonDecode(setJson);
    List<dynamic> diceData = set['dices'];

    setState(() {
      for (var dice in dices) {
        dice.controller.dispose();
      }
      dices = diceData.map((d) => Dice(
        maxValue: d['maxValue'],
        color: Color(d['color']),
        controller: AnimationController(
          duration: const Duration(milliseconds: 500),
          vsync: this,
        ),
      )).toList();
    });
    saveDices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: (RawKeyEvent event) {
            if (event is RawKeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              rollAllDices();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8F5E9), Colors.white],
              ),
            ),
            child: Stack(
              children: [
            Column(
            children: [
            AppBar(
            backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text('모두의 주사위', style: TextStyle(color: Colors.black)),
              actions: [
                IconButton(
                  icon: Icon(Icons.save, color: Colors.black),
                  onPressed: saveCurrentSet,
                ),
                IconButton(
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 32, color: Colors.black),
                      Icon(Icons.casino, size: 32, color: Colors.black),
                    ],
                  ),
                  onPressed: addDice,
                  iconSize: 48,
                ),
                IconButton(
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.remove, size: 32, color: Colors.black),
                      Icon(Icons.casino, size: 32, color: Colors.black),
                    ],
                  ),
                  onPressed: removeDice,
                  iconSize: 48,
                ),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 1;
                  if (dices.length > 1) crossAxisCount = 2;
                  if (dices.length > 4) crossAxisCount = 3;

                  double availableWidth = constraints.maxWidth - (crossAxisCount + 1) * 8.0;
                  double availableHeight = constraints.maxHeight - 80;
                  double diceSize = (availableWidth / crossAxisCount).floorToDouble() * 0.8;

                  if (diceSize * ((dices.length / crossAxisCount).ceil()) > availableHeight) {
                    diceSize = (availableHeight / ((dices.length / crossAxisCount).ceil())).floorToDouble() * 0.8;
                  }

                  return Padding(
                    padding: EdgeInsets.all(8.0),
                    child: AnimatedReorderableWrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dices.asMap().entries.map((entry) {
                        int index = entry.key;
                        Dice dice = entry.value;
                        return DiceWidget(
                          key: ValueKey(dice),
                          dice: dice,
                          size: diceSize,
                          onMaxValueChanged: (newValue) {
                            setState(() {
                              dice.maxValue = newValue;
                            });
                            saveDices();
                          },
                          onRoll: () => rollDice(dice),
                        );
                      }).toList(),
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final Dice item = dices.removeAt(oldIndex);
                          dices.insert(newIndex, item);
                        });
                        saveDices();
                      },
                    ),
                  );
                },
              ),
            ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: rollAllDices,
                    child: Text(
                      '모든 주사위 굴리기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        showSum = !showSum;
                      });
                    },
                    child: Text(
                      '주사위 합',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: showSum ? Colors.green : Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showSum)
      Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '주사위 합: ${calculateSum()}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ),
    Positioned(
    right: 16,
    bottom: 80,
    child: Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
    color: Colors.blue.withOpacity(0.2),
    borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButton<String>(
    hint: Text('저장된 Set 불러오기'),
    items: savedSets.map((String setJson) {
    Map<String, dynamic> set = jsonDecode(setJson);
    return DropdownMenuItem<String>(
    value: setJson,
    child: Text(set['name']),
    );
    }).toList(),
    onChanged: (String? newValue) {
    if (newValue != null) {
    loadSet(newValue);
    }
    },
      underline: Container(),
    ),
    ),
    ),
              ],
            ),
          ),
      ),
    );
  }
}

class Dice {
  int value = 1;
  int tempValue = 1;
  int maxValue = 6;
  Color color;
  AnimationController controller;

  Dice({
    this.maxValue = 6,
    Color? color,
    required this.controller,
  }) : color = color ?? Colors.red {
    tempValue = value;
  }

  void roll() {
    value = Random().nextInt(maxValue) + 1;
    tempValue = value;
  }
}

class DiceWidget extends StatelessWidget {
  final Dice dice;
  final double size;
  final Function(int) onMaxValueChanged;
  final VoidCallback onRoll;

  DiceWidget({
    Key? key,
    required this.dice,
    required this.size,
    required this.onMaxValueChanged,
    required this.onRoll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onRoll,
          child: AnimatedBuilder(
            animation: dice.controller,
            builder: (context, child) {
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(dice.controller.value * 2 * pi)
                  ..rotateY(dice.controller.value * 2 * pi)
                  ..rotateZ(dice.controller.value * 2 * pi),
                alignment: Alignment.center,
                child: CustomPaint(
                  painter: DicePainter(
                    dice: dice,
                    textColor: Colors.black,
                    shapeSizeRatio: 0.8,
                  ),
                  size: Size(size, size),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: EdgeInsets.only(top: 4, right: 4),
            child: DropdownButton<int>(
              value: dice.maxValue,
              items: [4, 6, 8, 10, 12, 20].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      shadows: [
                        Shadow(
                          blurRadius: 2.0,
                          color: Colors.white,
                          offset: Offset(1.0, 1.0),
                        ),
                        Shadow(
                          blurRadius: 2.0,
                          color: Colors.white,
                          offset: Offset(-1.0, -1.0),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  onMaxValueChanged(newValue);
                }
              },
              underline: Container(),
              icon: Icon(
                Icons.arrow_drop_down,
                color: Colors.black,
                size: 24,
              ),
              dropdownColor: Colors.white.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }
}

class DicePainter extends CustomPainter {
  final Dice dice;
  final Color textColor;
  final double shapeSizeRatio;

  DicePainter({
    required this.dice,
    required this.textColor,
    this.shapeSizeRatio = 0.8
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dice.color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final shapeSize = Size(size.width * shapeSizeRatio, size.height * shapeSizeRatio);
    final offsetX = (size.width - shapeSize.width) / 2;
    final offsetY = (size.height - shapeSize.height) / 2;

    canvas.translate(offsetX, offsetY);

    switch (dice.maxValue) {
      case 4:
        _drawTetrahedron(canvas, shapeSize, paint, shadowPaint);
        break;
      case 6:
        _drawCube(canvas, shapeSize, paint, shadowPaint);
        break;
      case 8:
        _drawOctahedron(canvas, shapeSize, paint, shadowPaint);
        break;
      case 10:
        _drawDecahedron(canvas, shapeSize, paint, shadowPaint);
        break;
      case 12:
        _drawDodecahedron(canvas, shapeSize, paint, shadowPaint);
        break;
      case 20:
        _drawIcosahedron(canvas, shapeSize, paint, shadowPaint);
        break;
      default:
        _drawCube(canvas, shapeSize, paint, shadowPaint);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: dice.tempValue.toString(),
        style: TextStyle(
          color: textColor,
          fontSize: shapeSize.width * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(shapeSize.width / 2 - textPainter.width / 2, shapeSize.height / 2 - textPainter.height / 2));
  }

  void _drawTetrahedron(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.2)
      ..lineTo(size.width * 0.2, size.height * 0.8)
      ..lineTo(size.width * 0.8, size.height * 0.8)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  void _drawCube(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.2)
      ..lineTo(size.width * 0.8, size.height * 0.2)
      ..lineTo(size.width * 0.8, size.height * 0.8)
      ..lineTo(size.width * 0.2, size.height * 0.8)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  void _drawOctahedron(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.2)
      ..lineTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.8)
      ..lineTo(size.width * 0.8, size.height * 0.5)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  void _drawDecahedron(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = i * 2 * pi / 10;
      final x = size.width / 2 + size.width * 0.4 * cos(angle);
      final y = size.height / 2 + size.height * 0.4 * sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  void _drawDodecahedron(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path();
    for (int i = 0; i < 12; i++) {
      final angle = i * 2 * pi / 12;
      final x = size.width / 2 + size.width * 0.45 * cos(angle);
      final y = size.height / 2 + size.height * 0.45 * sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  void _drawIcosahedron(Canvas canvas, Size size, Paint paint, Paint shadowPaint) {
    final path = Path();
    for (int i = 0; i < 20; i++) {
      final angle = i * 2 * pi / 20;
      final x = size.width / 2 + size.width * 0.48 * cos(angle);
      final y = size.height / 2 + size.height * 0.48 * sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(Offset(size.width * 0.02, size.height * 0.02)), shadowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class AnimatedReorderableWrap extends StatefulWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final Function(int oldIndex, int newIndex) onReorder;

  AnimatedReorderableWrap({
    required this.children,
    required this.onReorder,
    this.spacing = 0.0,
    this.runSpacing = 0.0,
  });

  @override
  _AnimatedReorderableWrapState createState() => _AnimatedReorderableWrapState();
}

class _AnimatedReorderableWrapState extends State<AnimatedReorderableWrap> {
  late List<Widget> _children;

  @override
  void initState() {
    super.initState();
    _children = List.from(widget.children);
  }

  @override
  void didUpdateWidget(AnimatedReorderableWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children != oldWidget.children) {
      _children = List.from(widget.children);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      children: _children.asMap().entries.map((entry) {
        final index = entry.key;
        final child = entry.value;
        return Draggable<int>(
          data: index,
          child: DragTarget<int>(
            builder: (context, candidateData, rejectedData) {
              return AnimatedSize(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: child,
              );
            },
            onWillAccept: (data) => data != null && data != index,
            onAccept: (data) {
              final oldIndex = data;
              final newIndex = index;
              widget.onReorder(oldIndex, newIndex);
              setState(() {
                final movedChild = _children.removeAt(oldIndex);
                _children.insert(newIndex, movedChild);
              });
            },
          ),
          feedback: Material(
            elevation: 4.0,
            child: Container(
              child: child,
            ),
          ),
          childWhenDragging: Container(
            width: 0,
            height: 0,
          ),
        );
      }).toList(),
    );
  }
}