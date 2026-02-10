import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart'; 

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FamilyTreeListScreen(),
  ));
}

// =======================
// 1. 数据模型
// =======================

enum Gender { male, female }

class Node {
  String id;
  String name;
  Gender gender;
  String? spouseId;
  List<String> childrenIds;
  int birthOrder;

  // 布局坐标
  double x = 0;
  double y = 0;
  
  // 临时计算属性
  double blockWidth = 0; 

  Node({
    required this.id,
    required this.name,
    required this.gender,
    this.spouseId,
    List<String>? childrenIds,
    this.birthOrder = 0,
  }) : childrenIds = childrenIds ?? [];
}

class TreeData {
  String id;
  String name;
  Map<String, Node> nodes;
  String rootId;

  TreeData({
    required this.id, 
    required this.name, 
    required this.nodes, 
    required this.rootId
  });
}

// =======================
// 2. 布局常量
// =======================

const double nodeWidth = 80;
const double nodeHeight = 40;
const double xSpacing = 20;    
const double ySpacing = 100;   
const double spouseGap = 40;   
const double spouseYOffset = 15; 
const double canvasPadding = 60.0; // 导出图片的内边距

// =======================
// 3. 布局引擎
// =======================

class LayoutEngine {
  final Map<String, Node> nodes;

  LayoutEngine(this.nodes);

  void calculateLayout(String rootId) {
    if (!nodes.containsKey(rootId)) return;
    _sortChildren(); 
    _calculateBlockSize(nodes[rootId]!);
    // 初始先以 0,0 为基准计算，后续在外部进行整体平移
    _calculateNodePosition(nodes[rootId]!, 0, 0);
  }

  void _sortChildren() {
    nodes.forEach((key, node) {
      if (node.childrenIds.isNotEmpty) {
        node.childrenIds.sort((a, b) {
          final nodeA = nodes[a];
          final nodeB = nodes[b];
          if (nodeA == null || nodeB == null) return 0;
          return nodeA.birthOrder.compareTo(nodeB.birthOrder);
        });
      }
    });
  }

  double _calculateBlockSize(Node node) {
    double mySelfWidth = nodeWidth;
    if (node.spouseId != null && nodes.containsKey(node.spouseId)) {
      mySelfWidth = nodeWidth + spouseGap + nodeWidth;
    }

    if (node.childrenIds.isEmpty) {
      node.blockWidth = mySelfWidth;
      return node.blockWidth;
    }

    double childrenTotalWidth = 0;
    for (var childId in node.childrenIds) {
      if (nodes.containsKey(childId)) {
        childrenTotalWidth += _calculateBlockSize(nodes[childId]!);
      }
    }
    if (node.childrenIds.length > 1) {
      childrenTotalWidth += (node.childrenIds.length - 1) * xSpacing;
    }

    node.blockWidth = max(mySelfWidth, childrenTotalWidth);
    return node.blockWidth;
  }

  void _calculateNodePosition(Node node, double centerX, double y) {
    double mySelfWidth = nodeWidth;
    bool hasSpouse = node.spouseId != null && nodes.containsKey(node.spouseId);
    if (hasSpouse) {
      mySelfWidth = nodeWidth + spouseGap + nodeWidth;
    }

    double blockLeft = centerX - node.blockWidth / 2;
    double selfStartOffset = (node.blockWidth - mySelfWidth) / 2;
    node.x = blockLeft + selfStartOffset;
    node.y = y;

    if (hasSpouse) {
      Node spouse = nodes[node.spouseId]!;
      spouse.x = node.x + nodeWidth + spouseGap;
      spouse.y = node.y + spouseYOffset; 
      spouse.blockWidth = 0; 
    }

    if (node.childrenIds.isEmpty) return;

    double childrenTotalWidth = _getChildrenTotalWidth(node);
    double currentChildX = centerX - childrenTotalWidth / 2;
    double nextLevelY = y + ySpacing;

    for (var childId in node.childrenIds) {
      if (nodes.containsKey(childId)) {
        var child = nodes[childId]!;
        double childCenterX = currentChildX + child.blockWidth / 2;
        _calculateNodePosition(child, childCenterX, nextLevelY);
        currentChildX += child.blockWidth + xSpacing;
      }
    }
  }

  double _getChildrenTotalWidth(Node node) {
    double w = 0;
    for (var id in node.childrenIds) {
      if (nodes.containsKey(id)) {
        w += nodes[id]!.blockWidth;
      }
    }
    if (node.childrenIds.length > 1) {
      w += (node.childrenIds.length - 1) * xSpacing;
    }
    return w;
  }
}

// =======================
// 4. 画笔
// =======================

class FamilyTreePainter extends CustomPainter {
  final Map<String, Node> nodes;
  final String rootId;

  FamilyTreePainter(this.nodes, this.rootId);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (nodes.containsKey(rootId)) {
      _drawRecursive(canvas, paint, nodes[rootId]!);
    }
  }

  void _drawRecursive(Canvas canvas, Paint paint, Node node) {
    bool hasSpouse = node.spouseId != null && nodes.containsKey(node.spouseId);
    
    if (hasSpouse) {
      final spouse = nodes[node.spouseId]!;
      final p1 = Offset(node.x + nodeWidth, node.y + nodeHeight / 2); 
      final p2 = Offset(spouse.x + nodeWidth / 2, spouse.y);
      final corner = Offset(p2.dx, p1.dy);

      final path = Path();
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(corner.dx, corner.dy); 
      path.lineTo(p2.dx, p2.dy);         
      canvas.drawPath(path, paint);
    }

    if (node.childrenIds.isNotEmpty) {
      double startX = node.x + nodeWidth / 2;
      double startY = node.y + nodeHeight;

      final firstChild = nodes[node.childrenIds.first];
      if (firstChild == null) return;
      
      final childTopY = firstChild.y;
      final midY = startY + (childTopY - startY) / 2;

      final firstChildNode = nodes[node.childrenIds.first]!;
      final lastChildNode = nodes[node.childrenIds.last]!;
      final lineLeftX = firstChildNode.x + nodeWidth / 2;
      final lineRightX = lastChildNode.x + nodeWidth / 2;

      canvas.drawLine(Offset(startX, startY), Offset(startX, midY), paint);

      if (startX < lineLeftX) {
        canvas.drawLine(Offset(startX, midY), Offset(lineLeftX, midY), paint);
      } else if (startX > lineRightX) {
        canvas.drawLine(Offset(startX, midY), Offset(lineRightX, midY), paint);
      }

      canvas.drawLine(Offset(lineLeftX, midY), Offset(lineRightX, midY), paint);

      for (var childId in node.childrenIds) {
        if (nodes.containsKey(childId)) {
          final child = nodes[childId]!;
          final childCenterX = child.x + nodeWidth / 2;
          canvas.drawLine(Offset(childCenterX, midY), Offset(childCenterX, child.y), paint);
          _drawRecursive(canvas, paint, child);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =======================
// 5. 族谱列表页
// =======================

class FamilyTreeListScreen extends StatefulWidget {
  const FamilyTreeListScreen({super.key});

  @override
  State<FamilyTreeListScreen> createState() => _FamilyTreeListScreenState();
}

class _FamilyTreeListScreenState extends State<FamilyTreeListScreen> {
  List<TreeData> trees = [];

  @override
  void initState() {
    super.initState();
    _addNewTree("示例族谱");
  }

  void _addNewTree(String name) {
    final rootId = const Uuid().v4();
    final rootNode = Node(id: rootId, name: "始祖", gender: Gender.male, birthOrder: 1);
    setState(() {
      trees.add(TreeData(
        id: const Uuid().v4(),
        name: name,
        nodes: {rootId: rootNode},
        rootId: rootId,
      ));
    });
  }

  void _renameTree(int index) {
    String newName = trees[index].name;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("重命名族谱"),
        content: TextField(
          controller: TextEditingController(text: newName),
          autofocus: true,
          onChanged: (v) => newName = v,
          decoration: const InputDecoration(labelText: "名称"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              if (newName.isNotEmpty) {
                setState(() => trees[index].name = newName);
              }
              Navigator.pop(ctx);
            }, 
            child: const Text("保存")
          ),
        ],
      )
    );
  }

  void _deleteTree(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除族谱"),
        content: Text("确定要删除「${trees[index].name}」吗？此操作不可撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              setState(() => trees.removeAt(index));
              Navigator.pop(ctx);
            }, 
            child: const Text("删除", style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("族谱列表")),
      body: trees.isEmpty 
        ? const Center(child: Text("暂无族谱，请点击右下角添加")) 
        : ListView.builder(
          itemCount: trees.length,
          itemBuilder: (ctx, i) => ListTile(
            leading: const Icon(Icons.account_tree, color: Colors.blue),
            title: Text(trees[i].name),
            subtitle: Text("节点数: ${trees[i].nodes.length}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.grey), onPressed: () => _renameTree(i)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteTree(i)),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FamilyTreeEditor(treeData: trees[i])),
              );
            },
          ),
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addNewTree("新族谱 ${trees.length + 1}"),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =======================
// 6. 编辑页面
// =======================

class FamilyTreeEditor extends StatefulWidget {
  final TreeData treeData;
  const FamilyTreeEditor({super.key, required this.treeData});

  @override
  State<FamilyTreeEditor> createState() => _FamilyTreeEditorState();
}

class _FamilyTreeEditorState extends State<FamilyTreeEditor> {
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  
  // 动态计算的画布尺寸，初始给个默认值
  double _canvasWidth = 1000.0;
  double _canvasHeight = 1000.0;

  @override
  void initState() {
    super.initState();
    // 布局并计算尺寸
    _performLayoutAndResize();
    
    // 初始居中
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _resetView();
    });
  }

  // 核心逻辑：布局 + 计算边界 + 平移 + 调整画布大小
  void _performLayoutAndResize() {
    if (widget.treeData.nodes.isEmpty) return;

    // 1. 先进行一次基础布局 (假设原点为 0,0)
    LayoutEngine(widget.treeData.nodes).calculateLayout(widget.treeData.rootId);

    // 2. 遍历所有节点，计算边界 (Bounding Box)
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (var node in widget.treeData.nodes.values) {
      // 检查节点本身
      minX = min(minX, node.x);
      minY = min(minY, node.y);
      maxX = max(maxX, node.x + nodeWidth);
      maxY = max(maxY, node.y + nodeHeight);

      // 如果有配偶，也要检查配偶的边界
      // (虽然 spouse 也是 nodes 里的一个 Node，循环会遍历到，但为了保险起见，逻辑覆盖)
    }

    if (minX == double.infinity) {
      // 异常情况，重置默认
      minX = 0; maxX = 100; minY = 0; maxY = 100;
    }

    // 3. 计算需要的偏移量，将树整体移到 (padding, padding)
    double shiftX = canvasPadding - minX;
    double shiftY = canvasPadding - minY;

    // 4. 应用偏移量到所有节点
    for (var node in widget.treeData.nodes.values) {
      node.x += shiftX;
      node.y += shiftY;
    }

    // 5. 计算最终画布大小 = 内容大小 + 2 * padding
    double contentWidth = maxX - minX;
    double contentHeight = maxY - minY;

    setState(() {
      _canvasWidth = contentWidth + (canvasPadding * 2);
      _canvasHeight = contentHeight + (canvasPadding * 2);
    });
  }

  void _updateNodeInfo(String nodeId, String newName, Gender newGender, int newOrder) {
    setState(() {
      if (widget.treeData.nodes.containsKey(nodeId)) {
        var node = widget.treeData.nodes[nodeId]!;
        node.name = newName;
        node.gender = newGender;
        node.birthOrder = newOrder;
      }
      _performLayoutAndResize();
    });
  }

  void _moveNode(Node node, bool isLeft) {
    String? parentId;
    for (var n in widget.treeData.nodes.values) {
      if (n.childrenIds.contains(node.id)) {
        parentId = n.id;
        break;
      }
    }
    if (parentId == null) return;

    var parent = widget.treeData.nodes[parentId]!;
    int index = parent.childrenIds.indexOf(node.id);
    
    setState(() {
      if (isLeft && index > 0) {
        var prevNode = widget.treeData.nodes[parent.childrenIds[index - 1]]!;
        int temp = node.birthOrder;
        node.birthOrder = prevNode.birthOrder;
        prevNode.birthOrder = temp;
      } else if (!isLeft && index < parent.childrenIds.length - 1) {
        var nextNode = widget.treeData.nodes[parent.childrenIds[index + 1]]!;
        int temp = node.birthOrder;
        node.birthOrder = nextNode.birthOrder;
        nextNode.birthOrder = temp;
      }
      _performLayoutAndResize();
    });
  }

  void _deleteNode(String nodeId) {
    setState(() {
      bool isChildOfSomeone = false;
      for (var n in widget.treeData.nodes.values) {
        if (n.childrenIds.contains(nodeId)) {
          isChildOfSomeone = true;
          break;
        }
      }
      bool isRoot = (nodeId == widget.treeData.rootId);
      
      if (!isRoot && !isChildOfSomeone) {
        for (var n in widget.treeData.nodes.values) {
          if (n.spouseId == nodeId) {
            n.spouseId = null;
            break;
          }
        }
        widget.treeData.nodes.remove(nodeId);
      } else {
        if (isRoot) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("不能删除根节点")));
          return;
        }

        String? parentId;
        for (var node in widget.treeData.nodes.values) {
          if (node.childrenIds.contains(nodeId)) {
            parentId = node.id;
            break;
          }
        }
        if (parentId != null) {
          widget.treeData.nodes[parentId]!.childrenIds.remove(nodeId);
        }
        _recursiveRemove(nodeId);
      }
      _performLayoutAndResize();
    });
  }

  void _recursiveRemove(String targetId) {
    if (!widget.treeData.nodes.containsKey(targetId)) return;
    final node = widget.treeData.nodes[targetId]!;
    
    if (node.spouseId != null) {
      String sId = node.spouseId!;
      node.spouseId = null; 
      if (widget.treeData.nodes.containsKey(sId)) {
        widget.treeData.nodes[sId]!.spouseId = null; 
        _recursiveRemove(sId); 
      }
    }
    for (var childId in List.of(node.childrenIds)) {
      _recursiveRemove(childId);
    }
    widget.treeData.nodes.remove(targetId);
  }

  void _addNode(String baseNodeId, String name, Gender gender, String relation, int order) {
    final newNodeId = const Uuid().v4();
    final newNode = Node(id: newNodeId, name: name, gender: gender, birthOrder: order);

    setState(() {
      widget.treeData.nodes[newNodeId] = newNode;
      final baseNode = widget.treeData.nodes[baseNodeId]!;

      if (relation == "配偶") {
        baseNode.spouseId = newNodeId;
        newNode.spouseId = baseNodeId;
      } 
      else if (relation == "子女") {
        baseNode.childrenIds.add(newNodeId);
      } 
      else if (relation == "兄弟姐妹") {
        String? parentId;
        for (var n in widget.treeData.nodes.values) {
          if (n.childrenIds.contains(baseNodeId)) {
            parentId = n.id;
            break;
          }
        }
        if (parentId != null) {
          widget.treeData.nodes[parentId]!.childrenIds.add(newNodeId);
        }
      }
      else if (relation == "父亲") {
        newNode.childrenIds.add(baseNodeId);
        widget.treeData.rootId = newNodeId;
      }
      _performLayoutAndResize();
    });
  }

  Future<void> _exportImage() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      
      Uint8List pngBytes = byteData.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imgFile = File('${directory.path}/tree_${DateTime.now().millisecondsSinceEpoch}.png');
      await imgFile.writeAsBytes(pngBytes);

      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      
      await Gal.putImage(imgFile.path);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已保存到系统相册")));
      }
    } catch (e) {
      debugPrint("Export Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("保存失败: $e")));
      }
    }
  }

  void _resetView() {
     final viewportWidth = MediaQuery.of(context).size.width;
    //  final viewportHeight = MediaQuery.of(context).size.height;
     
     // 计算居中偏移：(画布宽 - 屏幕宽) / 2
     final x = (_canvasWidth - viewportWidth) / 2;
     // 垂直方向也稍微居中一点，或者留点顶部空间
     final y = 50.0;

     _transformationController.value = Matrix4.identity()
       ..translateByVector3(vm.Vector3(-x, -y, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.treeData.name),
        actions: [
          IconButton(icon: const Icon(Icons.center_focus_weak), onPressed: _resetView),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportImage),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformationController,
        boundaryMargin: const EdgeInsets.all(500), // 允许拖出边界
        minScale: 0.1,
        maxScale: 5.0,
        constrained: false, 
        child: RepaintBoundary(
          key: _repaintBoundaryKey,
          child: Container(
            color: Colors.white,
            // 关键修改：使用动态计算的尺寸
            width: _canvasWidth, 
            height: _canvasHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FamilyTreePainter(widget.treeData.nodes, widget.treeData.rootId),
                  ),
                ),
                ...widget.treeData.nodes.values.map((node) {
                  return Positioned(
                    left: node.x,
                    top: node.y,
                    child: GestureDetector(
                      onTap: () => _showNodeOptions(context, node),
                      child: _buildNodeWidget(node),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeWidget(Node node) {
    final isMale = node.gender == Gender.male;
    final color = isMale ? Colors.blue : Colors.pinkAccent;
    return Container(
      width: nodeWidth,
      height: nodeHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ]
      ),
      alignment: Alignment.center,
      child: Text(
        node.name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  void _showNodeOptions(BuildContext context, Node currentNode) {
    final nameController = TextEditingController(text: currentNode.name);
    final orderController = TextEditingController(text: currentNode.birthOrder.toString());
    Gender selectedGender = currentNode.gender;

    bool isRoot = (currentNode.id == widget.treeData.rootId);
    bool isChildOfSomeone = false;
    for(var n in widget.treeData.nodes.values) {
      if (n.childrenIds.contains(currentNode.id)) {
        isChildOfSomeone = true;
        break;
      }
    }
    
    bool isSpouseNode = !isRoot && !isChildOfSomeone;
    bool hasSpouse = (currentNode.spouseId != null);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("编辑节点"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("基本信息", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "名字", border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (!isSpouseNode)
                        Expanded(
                          child: TextField(
                            controller: orderController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "排行", border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        if (!isSpouseNode) const SizedBox(width: 10),
                        
                        if (!isSpouseNode && !isRoot) ...[
                          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
                            Navigator.pop(context);
                            _moveNode(currentNode, true);
                          }, tooltip: "向左换位"),
                          IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () {
                            Navigator.pop(context);
                            _moveNode(currentNode, false);
                          }, tooltip: "向右换位"),
                        ]
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ChoiceChip(label: const Text("男"), selected: selectedGender == Gender.male, onSelected: (b) => setState(() => selectedGender = Gender.male)),
                        const SizedBox(width: 10),
                        ChoiceChip(label: const Text("女"), selected: selectedGender == Gender.female, onSelected: (b) => setState(() => selectedGender = Gender.female)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: () {
                          int order = int.tryParse(orderController.text) ?? currentNode.birthOrder;
                          _updateNodeInfo(currentNode.id, nameController.text, selectedGender, order);
                          Navigator.pop(context);
                        },
                        child: const Text("保存修改", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    
                    const Divider(height: 20),
                    
                    if (!isSpouseNode) ...[
                      const Text("添加关系", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (!hasSpouse) 
                          OutlinedButton(
                            child: const Text("加配偶"),
                            onPressed: () => _showAddConfirmDialog(context, currentNode, "配偶"),
                          ),
                          OutlinedButton(
                            child: const Text("加子女"),
                            onPressed: () => _showAddConfirmDialog(context, currentNode, "子女"),
                          ),
                          if (!isRoot) 
                          OutlinedButton(
                            child: const Text("加兄弟姐妹"),
                            onPressed: () => _showAddConfirmDialog(context, currentNode, "兄弟姐妹"),
                          ),
                          if (isRoot)
                            OutlinedButton(
                              child: const Text("加父亲(向上)"),
                              onPressed: () => _showAddConfirmDialog(context, currentNode, "父亲"),
                            ),
                        ],
                      ),
                      const Divider(height: 20),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: Text(isSpouseNode ? "删除配偶" : "删除此节点", style: const TextStyle(color: Colors.red)),
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeleteConfirm(context, currentNode.id, isSpouseNode);
                        },
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showAddConfirmDialog(BuildContext context, Node currentNode, String relation) {
    String newName = "";
    Gender newGender = Gender.male;
    bool isSpouse = (relation == "配偶");
    int newOrder = 1;

    if (relation == "子女") {
      newOrder = currentNode.childrenIds.length + 1;
    } else if (relation == "兄弟姐妹") {
       for(var n in widget.treeData.nodes.values) {
         if (n.childrenIds.contains(currentNode.id)) {
           newOrder = n.childrenIds.length + 1;
           break;
         }
       }
    }

    if (isSpouse) {
      newGender = currentNode.gender == Gender.male ? Gender.female : Gender.male;
    }

    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text("添加$relation"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: "名字", border: OutlineInputBorder()),
                onChanged: (v) => newName = v,
              ),
              const SizedBox(height: 10),
              if (!isSpouse)
                TextField(
                  decoration: InputDecoration(
                    labelText: "排行(1,2...)", 
                    border: const OutlineInputBorder(),
                    errorText: errorText
                  ),
                  controller: TextEditingController(text: newOrder.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    newOrder = int.tryParse(v) ?? 1;
                    setState(() => errorText = null);
                  },
                ),
              if (!isSpouse) const SizedBox(height: 10),
              Row(
                children: [
                  ChoiceChip(label: const Text("男"), selected: newGender == Gender.male, onSelected: (b) => setState(() => newGender = Gender.male)),
                  const SizedBox(width: 10),
                  ChoiceChip(label: const Text("女"), selected: newGender == Gender.female, onSelected: (b) => setState(() => newGender = Gender.female)),
                ],
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            ElevatedButton(
              onPressed: () {
                if (newName.isEmpty) return;

                if (!isSpouse) {
                  List<int> existingOrders = [];
                  if (relation == "子女") {
                    existingOrders = currentNode.childrenIds.map((id) => widget.treeData.nodes[id]!.birthOrder).toList();
                  } else if (relation == "兄弟姐妹") {
                    for(var n in widget.treeData.nodes.values) {
                      if (n.childrenIds.contains(currentNode.id)) {
                        existingOrders = n.childrenIds.map((id) => widget.treeData.nodes[id]!.birthOrder).toList();
                        break;
                      }
                    }
                  }

                  if (existingOrders.contains(newOrder)) {
                    setState(() {
                      existingOrders.sort();
                      errorText = "$newOrder 已存在 (当前已用: ${existingOrders.join(', ')})";
                    });
                    return; 
                  }
                }

                _addNode(currentNode.id, newName, newGender, relation, newOrder);
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text("确定"),
            ),
          ],
        )
      )
    );
  }

  void _showDeleteConfirm(BuildContext context, String nodeId, bool isSpouse) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除?"),
        content: Text(isSpouse 
          ? "删除配偶将保留其子女和主节点。" 
          : "删除主节点将一并删除其所有后代节点，此操作无法撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteNode(nodeId);
            }, 
            child: const Text("删除", style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );
  }
}