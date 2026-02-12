import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/settings_service.dart';

/// 방장 설정 시트 (내보내기 허용/차단, 워터마크 강제, 로그 공개)
/// owner/admin만 표시·저장 가능
/// [onCanvasReset]: 캔버스 초기화 성공 시 로컬 상태 정리를 위해 호출 (캔버스 화면에서 전달)
void showRoomHostSettingsSheet(
  BuildContext context,
  RoomModel room, {
  void Function()? onCanvasReset,
}) {
  final authProvider = context.read<AuthProvider>();
  final myUserId = authProvider.user?.uid ?? '';
  final myRole = room.members[myUserId]?.role;
  final isHost = myRole == MemberRole.owner || myRole == MemberRole.admin;

  if (!isHost) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('방장만 설정을 변경할 수 있습니다.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  bool exportAllowed = room.exportAllowed;
  bool watermarkForced = room.watermarkForced;
  bool logPublic = room.logPublic;
  bool canEditShapes = room.canEditShapes;
  CanvasExpandMode canvasExpandMode = room.canvasExpandMode == 'free'
      ? CanvasExpandMode.free
      : CanvasExpandMode.rectangular;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 20, color: AppColors.gold),
                      const SizedBox(width: 8),
                      const Text(
                        '방장 설정',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('내보내기 허용'),
                    subtitle: const Text('멤버가 캔버스를 이미지/PDF로 내보낼 수 있음'),
                    value: exportAllowed,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => exportAllowed = v),
                  ),
                  SwitchListTile(
                    title: const Text('워터마크 강제'),
                    subtitle: const Text('내보내기 시 워터마크를 반드시 포함'),
                    value: watermarkForced,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => watermarkForced = v),
                  ),
                  SwitchListTile(
                    title: const Text('로그 공개'),
                    subtitle: const Text('시간순 로그(타임라인)를 멤버에게 공개'),
                    value: logPublic,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => logPublic = v),
                  ),
                  SwitchListTile(
                    title: const Text('도형 수정 허용'),
                    subtitle: const Text('멤버가 도형을 추가·수정·삭제할 수 있음'),
                    value: canEditShapes,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => canEditShapes = v),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      '캔버스 확장 방식',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  RadioListTile<CanvasExpandMode>(
                    title: const Text('사각 확장'),
                    subtitle: const Text('캔버스를 사각형 영역 단위로 확장'),
                    value: CanvasExpandMode.rectangular,
                    groupValue: canvasExpandMode,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => canvasExpandMode = v!),
                  ),
                  RadioListTile<CanvasExpandMode>(
                    title: const Text('자유 확장'),
                    subtitle: const Text('무한 캔버스 방식으로 자유롭게 확장'),
                    value: CanvasExpandMode.free,
                    groupValue: canvasExpandMode,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setModalState(() => canvasExpandMode = v!),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.cleaning_services_outlined, color: AppColors.gold),
                    title: const Text('캔버스 초기화'),
                    subtitle: const Text('캔버스의 모든 손글씨·도형·텍스트·미디어를 삭제합니다. 되돌릴 수 없습니다.'),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('캔버스 초기화'),
                          content: const Text(
                            '이 방의 캔버스에 있는 모든 손글씨·도형·텍스트·미디어가 삭제됩니다.\n\n이 작업은 되돌릴 수 없습니다. 계속하시겠습니까?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('초기화'),
                            ),
                          ],
                        ),
                      );
                      if (!context.mounted || confirmed != true) return;
                      final roomProvider = context.read<RoomProvider>();
                      final success = await roomProvider.resetCanvas(room.id, myUserId);
                      if (!context.mounted) return;
                      if (success) onCanvasReset?.call();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success ? '캔버스가 초기화되었습니다.' : '캔버스 초기화에 실패했습니다.'),
                          backgroundColor: success ? null : Colors.red,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final roomProvider = context.read<RoomProvider>();
                        await roomProvider.updateRoom(
                          room.id,
                          exportAllowed: exportAllowed,
                          watermarkForced: watermarkForced,
                          logPublic: logPublic,
                          canEditShapes: canEditShapes,
                          canvasExpandMode: canvasExpandMode.name,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.paper,
                      ),
                      child: const Text('저장'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
      );
    },
  );
}
