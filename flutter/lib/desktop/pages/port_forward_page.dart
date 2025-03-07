import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:wakelock/wakelock.dart';

const double _kColumn1Width = 30;
const double _kColumn4Width = 100;
const double _kRowHeight = 50;
const double _kTextLeftMargin = 20;

class _PortForward {
  int localPort;
  String remoteHost;
  int remotePort;

  _PortForward.fromJson(List<dynamic> json)
      : localPort = json[0] as int,
        remoteHost = json[1] as String,
        remotePort = json[2] as int;
}

class PortForwardPage extends StatefulWidget {
  const PortForwardPage({Key? key, required this.id, required this.isRDP})
      : super(key: key);
  final String id;
  final bool isRDP;

  @override
  State<PortForwardPage> createState() => _PortForwardPageState();
}

class _PortForwardPageState extends State<PortForwardPage>
    with AutomaticKeepAliveClientMixin {
  final bool isRdp = false;
  final TextEditingController localPortController = TextEditingController();
  final TextEditingController remoteHostController = TextEditingController();
  final TextEditingController remotePortController = TextEditingController();
  RxList<_PortForward> pfs = RxList.empty(growable: true);
  late FFI _ffi;

  @override
  void initState() {
    super.initState();
    _ffi = FFI();
    _ffi.connect(widget.id, isPortForward: true);
    Get.put(_ffi, tag: 'pf_${widget.id}');
    if (!Platform.isLinux) {
      Wakelock.enable();
    }
    print("init success with id ${widget.id}");
  }

  @override
  void dispose() {
    _ffi.close();
    _ffi.dialogManager.dismissAll();
    if (!Platform.isLinux) {
      Wakelock.disable();
    }
    Get.delete<FFI>(tag: 'pf_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Overlay(initialEntries: [
      OverlayEntry(builder: (context) {
        _ffi.dialogManager.setOverlayState(Overlay.of(context));
        return Scaffold(
          backgroundColor: MyTheme.color(context).grayBg,
          body: FutureBuilder(future: () async {
            if (!isRdp) {
              refreshTunnelConfig();
            }
          }(), builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Container(
                decoration: BoxDecoration(
                    border: Border.all(
                        width: 20, color: MyTheme.color(context).grayBg!)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildPrompt(context),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                            color: MyTheme.color(context).bg,
                            border:
                                Border.all(width: 1, color: MyTheme.border)),
                        child: widget.isRDP
                            ? buildRdp(context)
                            : buildTunnel(context),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const Offstage();
          }),
        );
      })
    ]);
  }

  buildPrompt(BuildContext context) {
    return Obx(() => Offstage(
          offstage: pfs.isEmpty && !widget.isRDP,
          child: Container(
              height: 45,
              color: const Color(0xFF007F00),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('Listening ...'),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      translate('not_close_tcp_tip'),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFDDDDDD), height: 1.2),
                    )
                  ])).marginOnly(bottom: 8),
        ));
  }

  buildTunnel(BuildContext context) {
    text(String lable) => Expanded(
        child: Text(translate(lable)).marginOnly(left: _kTextLeftMargin));

    return Theme(
      data: Theme.of(context)
          .copyWith(backgroundColor: MyTheme.color(context).bg),
      child: Obx(() => ListView.builder(
          itemCount: pfs.length + 2,
          itemBuilder: ((context, index) {
            if (index == 0) {
              return Container(
                height: 25,
                color: MyTheme.color(context).grayBg,
                child: Row(children: [
                  text('Local Port'),
                  const SizedBox(width: _kColumn1Width),
                  text('Remote Host'),
                  text('Remote Port'),
                  SizedBox(
                      width: _kColumn4Width, child: Text(translate('Action')))
                ]),
              );
            } else if (index == 1) {
              return buildTunnelAddRow(context);
            } else {
              return buildTunnelDataRow(context, pfs[index - 2], index - 2);
            }
          }))),
    );
  }

  buildTunnelAddRow(BuildContext context) {
    var portInputFormatter = [
      FilteringTextInputFormatter.allow(RegExp(
          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
    ];

    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(color: MyTheme.color(context).bg),
      child: Row(children: [
        buildTunnelInputCell(context,
            controller: localPortController,
            inputFormatters: portInputFormatter),
        const SizedBox(
            width: _kColumn1Width, child: Icon(Icons.arrow_forward_sharp)),
        buildTunnelInputCell(context,
            controller: remoteHostController, hint: 'localhost'),
        buildTunnelInputCell(context,
            controller: remotePortController,
            inputFormatters: portInputFormatter),
        SizedBox(
          width: _kColumn4Width,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                elevation: 0, side: const BorderSide(color: MyTheme.border)),
            onPressed: () async {
              int? localPort = int.tryParse(localPortController.text);
              int? remotePort = int.tryParse(remotePortController.text);
              if (localPort != null &&
                  remotePort != null &&
                  (remoteHostController.text.isEmpty ||
                      remoteHostController.text.trim().isNotEmpty)) {
                await bind.sessionAddPortForward(
                    id: 'pf_${widget.id}',
                    localPort: localPort,
                    remoteHost: remoteHostController.text.trim().isEmpty
                        ? 'localhost'
                        : remoteHostController.text.trim(),
                    remotePort: remotePort);
                localPortController.clear();
                remoteHostController.clear();
                remotePortController.clear();
                refreshTunnelConfig();
              }
            },
            child: Text(
              translate('Add'),
            ),
          ).marginAll(10),
        ),
      ]),
    );
  }

  buildTunnelInputCell(BuildContext context,
      {required TextEditingController controller,
      List<TextInputFormatter>? inputFormatters,
      String? hint}) {
    return Expanded(
      child: TextField(
        controller: controller,
        inputFormatters: inputFormatters,
        cursorColor: MyTheme.color(context).text,
        cursorHeight: 20,
        cursorWidth: 1,
        decoration: InputDecoration(
            border: OutlineInputBorder(
                borderSide: BorderSide(color: MyTheme.color(context).border!)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: MyTheme.color(context).border!)),
            fillColor: MyTheme.color(context).bg,
            contentPadding: const EdgeInsets.all(10),
            hintText: hint,
            hintStyle: TextStyle(
                color: MyTheme.color(context).placeholder, fontSize: 16)),
        style: TextStyle(color: MyTheme.color(context).text, fontSize: 16),
      ).marginAll(10),
    );
  }

  Widget buildTunnelDataRow(BuildContext context, _PortForward pf, int index) {
    text(String lable) => Expanded(
        child: Text(lable, style: const TextStyle(fontSize: 20))
            .marginOnly(left: _kTextLeftMargin));

    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
          color: index % 2 == 0
              ? isDarkTheme()
                  ? const Color(0xFF202020)
                  : const Color(0xFFF4F5F6)
              : MyTheme.color(context).bg),
      child: Row(children: [
        text(pf.localPort.toString()),
        const SizedBox(width: _kColumn1Width),
        text(pf.remoteHost),
        text(pf.remotePort.toString()),
        SizedBox(
          width: _kColumn4Width,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              await bind.sessionRemovePortForward(
                  id: 'pf_${widget.id}', localPort: pf.localPort);
              refreshTunnelConfig();
            },
          ),
        ),
      ]),
    );
  }

  void refreshTunnelConfig() async {
    String peer = await bind.mainGetPeer(id: widget.id);
    Map<String, dynamic> config = jsonDecode(peer);
    List<dynamic> infos = config['port_forwards'] as List;
    List<_PortForward> result = List.empty(growable: true);
    for (var e in infos) {
      result.add(_PortForward.fromJson(e));
    }
    pfs.value = result;
  }

  buildRdp(BuildContext context) {
    text1(String lable) =>
        Expanded(child: Text(lable).marginOnly(left: _kTextLeftMargin));
    text2(String lable) => Expanded(
            child: Text(
          lable,
          style: TextStyle(fontSize: 20),
        ).marginOnly(left: _kTextLeftMargin));
    return Theme(
      data: Theme.of(context)
          .copyWith(backgroundColor: MyTheme.color(context).bg),
      child: ListView.builder(
          itemCount: 2,
          itemBuilder: ((context, index) {
            if (index == 0) {
              return Container(
                height: 25,
                color: MyTheme.color(context).grayBg,
                child: Row(children: [
                  text1('Local Port'),
                  const SizedBox(width: _kColumn1Width),
                  text1('Remote Host'),
                  text1('Remote Port'),
                ]),
              );
            } else {
              return Container(
                height: _kRowHeight,
                decoration: BoxDecoration(color: MyTheme.color(context).bg),
                child: Row(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 120,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              elevation: 0,
                              side: const BorderSide(color: MyTheme.border)),
                          onPressed: () {},
                          child: Text(
                            translate('New RDP'),
                            style: TextStyle(
                                fontWeight: FontWeight.w300, fontSize: 14),
                          ),
                        ).marginSymmetric(vertical: 10),
                      ).marginOnly(left: 20),
                    ),
                  ),
                  const SizedBox(
                      width: _kColumn1Width,
                      child: Icon(Icons.arrow_forward_sharp)),
                  text2('localhost'),
                  text2('RDP'),
                ]),
              );
            }
          })),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
