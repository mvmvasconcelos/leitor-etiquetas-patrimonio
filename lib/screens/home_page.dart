/// Tela principal do aplicativo onde o usuário escaneia e gerencia os códigos de barras.
/// 
/// Apresenta a lista de códigos escaneados e fornece a interface para escanear novos códigos,
/// além de gerenciar operações como seleção, cópia e exclusão.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../providers/update_provider.dart';
import '../utils/feedback_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Registrar para observar mudanças no ciclo de vida do app
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Remover observador ao destruir o widget
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando o app é retomado do background
    if (state == AppLifecycleState.resumed) {
      // Verificar se a atualização foi concluída
      final updateProvider = Provider.of<UpdateProvider>(context, listen: false);
      updateProvider.checkIfUpdated();
    }
  }

  Future<void> _scanBarcode(BuildContext context) async {
    final provider = Provider.of<ScannerProvider>(context, listen: false);
    
    try {
      final barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        '#1B5E20', // Cor do botão (verde IFSUL)
        'Cancelar',
        true,
        ScanMode.BARCODE,
      );

      // Se o usuário cancelou o scan
      if (barcodeScanRes == '-1') return;
      
      // Adicionar o código escaneado antes de qualquer feedback
      provider.addScan(barcodeScanRes);
      
      // Depois do scan bem-sucedido, dar feedback
      if (provider.hapticFeedbackEnabled) {
        await FeedbackUtils.provideHapticFeedback();
      }
      
      // Feedback sonoro
      if (provider.soundFeedbackEnabled) {
        await FeedbackUtils.provideSoundFeedback();
      }
    } on PlatformException catch (e) {
      debugPrint('Erro de plataforma ao escanear: $e');
      // Tratar erros de plataforma
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao scanear. Tente novamente.'),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao escanear: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString()}'),
        ),
      );
    }
  }

  void _copySelectedToClipboard(BuildContext context) {
    final provider = Provider.of<ScannerProvider>(context, listen: false);
    final selectedScans = provider.getSelectedScans();
    
    if (selectedScans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum código selecionado'),
        ),
      );
      return;
    }
    
    // Juntar os códigos com quebras de linha sem pontuação ou separadores
    final textToCopy = selectedScans.join('\n');
    
    Clipboard.setData(ClipboardData(text: textToCopy)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selectedScans.length} código(s) copiado(s) para a área de transferência'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }
  
  void _deleteSelected(BuildContext context) {
    final provider = Provider.of<ScannerProvider>(context, listen: false);
    final count = provider.removeSelected();
    
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count código(s) removido(s)'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ScannerProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leitor de Etiquetas de Patrimônio'),
        backgroundColor: colorScheme.primaryContainer,
        actions: provider.isSelectionMode && provider.scans.isNotEmpty
            ? [
                // Botão de copiar
                IconButton(
                  icon: Icon(Icons.copy, color: colorScheme.onPrimaryContainer),
                  onPressed: () => _copySelectedToClipboard(context),
                  tooltip: 'Copiar selecionados',
                ),
                // Botão de excluir
                IconButton(
                  icon: Icon(Icons.delete, color: colorScheme.error),
                  onPressed: () => _deleteSelected(context),
                  tooltip: 'Excluir selecionados',
                ),
                // Botão para limpar seleção
                IconButton(
                  icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer),
                  onPressed: () => provider.toggleSelectionMode(false),
                  tooltip: 'Cancelar seleção',
                ),
              ]
            : [
                // Menu principal unificado
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'settings') {
                      Navigator.pushNamed(context, '/settings');
                    } else if (value == 'about') {
                      Navigator.pushNamed(context, '/about');
                    } else if (value == 'select_all' && provider.scans.isNotEmpty) {
                      provider.toggleSelectionMode(true);
                      provider.selectAll(true);
                    } else if (value == 'delete_all' && provider.scans.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Apagar todos os códigos?'),
                          content: const Text('Esta ação não pode ser desfeita.'),
                          actions: [
                            TextButton(
                              child: const Text('CANCELAR'),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                            TextButton(
                              child: const Text('APAGAR'),
                              onPressed: () {
                                provider.clearScans();
                                Navigator.of(ctx).pop();
                              },
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    if (provider.scans.isNotEmpty) ...[
                      const PopupMenuItem(
                        value: 'select_all',
                        child: ListTile(
                          leading: Icon(Icons.select_all),
                          title: Text('Selecionar todos'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete_all',
                        child: ListTile(
                          leading: Icon(Icons.delete_forever),
                          title: Text('Apagar todos'),
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings),
                        title: Text('Configurações'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'about',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Sobre'),
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          // Botão para o modo avançado - comentado temporariamente conforme o ROADMAP
          // Descomentar quando a funcionalidade estiver pronta para ser lançada
          /*
          if (!provider.isSelectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/advanced'),
                icon: const Icon(Icons.view_module),
                label: const Text('Modo Avançado'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          */
          Expanded(
            child: provider.scans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 80,
                        color: colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhum código escaneado.\nAperte o botão abaixo para começar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (provider.isSelectionMode) 
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: provider.areAllSelected(),
                              onChanged: (value) => provider.selectAll(value ?? false),
                            ),
                            Text(
                              'Selecionar todos (${provider.selectedCount}/${provider.scans.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: provider.scans.length,
                        itemBuilder: (context, index) {
                          final scan = provider.scans[index];
                          final isSelected = provider.isSelected(index);
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: isSelected ? 4 : 1,
                            color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
                            child: InkWell(
                              onLongPress: () {
                                if (!provider.isSelectionMode) {
                                  provider.toggleSelectionMode(true);
                                  provider.toggleSelection(index);
                                }
                              },
                              onTap: () {
                                if (provider.isSelectionMode) {
                                  provider.toggleSelection(index);
                                }
                              },
                              child: ListTile(
                                leading: provider.isSelectionMode
                                    ? Checkbox(
                                        value: isSelected,
                                        onChanged: (bool? value) {
                                          provider.toggleSelection(index);
                                        },
                                      )
                                    : CircleAvatar(
                                        backgroundColor: colorScheme.primary,
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                title: Text(
                                  scan,
                                  style: TextStyle(
                                    fontSize: 16, 
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                trailing: provider.isSelectionMode
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy, size: 20),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: scan))
                                                  .then((_) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Código copiado'),
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              });
                                            },
                                            tooltip: 'Copiar código',
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete, size: 20, color: colorScheme.error),
                                            onPressed: () => provider.removeScan(index),
                                            tooltip: 'Excluir código',
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: provider.isSelectionMode
            ? null
            : () => _scanBarcode(context),
        backgroundColor: provider.isSelectionMode 
            ? colorScheme.surfaceVariant
            : colorScheme.primary,
        foregroundColor: provider.isSelectionMode 
            ? colorScheme.onSurfaceVariant.withOpacity(0.5)
            : colorScheme.onPrimary,
        label: const Text('Escanear'),
        icon: const Icon(Icons.qr_code_scanner),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}