import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  List<Dice> dices = [Dice()];
  final Random random = Random();
  late AnimationController _controller;
  late Animation<double> _animation;
  late AudioPlayer _audioPlayer;
  List<String> savedSets = [];

  @override
  void initState() {
    super.initState();
    loadDices();
    loadSavedSets();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _audioPlayer = AudioPlayer();
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    await _audioPlayer.setAsset('assets/dice_roll.mp3');
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void loadDices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt('diceCount') ?? 1;
    List<int> maxValues = prefs.getStringList('diceMaxValues')?.map(int.parse).toList() ?? [6];

    setState(() {
      dices = List.generate(count, (index) => Dice(maxValue: maxValues[index], color: getRandomColor()));
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
        dices.add(Dice(color: getRandomColor()));
      });
      saveDices();
    }
  }

  void removeDice() {
    if (dices.length > 1) {
      setState(() {
        dices.removeLast();
      });
      saveDices();
    }
  }

  Future<void> animateDiceRoll(List<Dice> dicesToRoll) async {
    _controller.reset();
    _controller.forward();

    await _audioPlayer.stop();
    await _audioPlayer.seek(Duration.zero);
    await _audioPlayer.play();

    for (int i = 0; i < 10; i++) {
      await Future.delayed(Duration(milliseconds: 50));
      setState(() {
        for (var dice in dicesToRoll) {
          dice.tempValue = random.nextInt(dice.maxValue) + 1;
        }
      });
    }

    setState(() {
      for (var dice in dicesToRoll) {
        dice.roll();
      }
    });
  }

  Future<void> rollDice(Dice dice) async {
    await animateDiceRoll([dice]);
  }

  Future<void> rollAllDices() async {
    await animateDiceRoll(dices);
  }

  Color getRandomColor() {
    return Color.fromARGB(
      255,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
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
      dices = diceData.map((d) => Dice(maxValue: d['maxValue'], color: Color(d['color']))).toList();
    });
    saveDices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('주사위 앱'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: saveCurrentSet,
          ),
          IconButton(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 32),
                Icon(Icons.casino, size: 32),
              ],
            ),
            onPressed: addDice,
            iconSize: 48,
          ),
          IconButton(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.remove, size: 32),
                Icon(Icons.casino, size: 32),
              ],
            ),
            onPressed: removeDice,
            iconSize: 48,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount = 1;
                    if (dices.length > 1) crossAxisCount = 2;
                    if (dices.length > 4) crossAxisCount = 3;

                    double availableWidth = constraints.maxWidth - (crossAxisCount + 1) * 8.0;
                    double availableHeight = constraints.maxHeight - 80; // 버튼을 위한 공간 확보
                    double diceSize = (availableWidth / crossAxisCount).floorToDouble();

                    if (diceSize * ((dices.length / crossAxisCount).ceil()) > availableHeight) {
                      diceSize = (availableHeight / ((dices.length / crossAxisCount).ceil())).floorToDouble();
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
              child: ElevatedButton(
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
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
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
                underline: Container(), // 밑줄 제거
              ),
            ),
          ),
        ],
      ),
    );
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

class Dice {
  int value = 1;
  int tempValue = 1;
  int maxValue = 6;
  Color color;

  Dice({this.maxValue = 6, Color? color}) : color = color ?? Colors.red;

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

  Color getTextColor(Color backgroundColor) {
    double luminance = (0.299 * backgroundColor.red +
        0.587 * backgroundColor.green +
        0.114 * backgroundColor.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = getTextColor(dice.color);
    return GestureDetector(
      onTap: onRoll,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: dice.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Padding(
                  padding: EdgeInsets.all(size * 0.1),
                  child: Text(
                    '${dice.tempValue}',
                    style: TextStyle(
                      fontSize: size * 0.5,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: DropdownButton<int>(
                value: dice.maxValue,
                items: [4, 6, 8, 10, 12, 20].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('1-$value', style: TextStyle(color: textColor)),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    onMaxValueChanged(newValue);
                  }
                },
                dropdownColor: dice.color,
                icon: Icon(Icons.arrow_drop_down, color: textColor),
                underline: Container(height: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}