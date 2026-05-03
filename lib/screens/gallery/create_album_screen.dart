import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme.dart';
import '../../models/gallery_album.dart';
import '../../services/gallery_service.dart';

class CreateAlbumScreen extends StatefulWidget {
  final String    userEmail;
  final GalleryAlbum? editAlbum; // null = create, non-null = edit

  const CreateAlbumScreen({
    super.key,
    required this.userEmail,
    this.editAlbum,
  });

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _titleCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _service    = GalleryService();
  final _picker     = ImagePicker();

  DateTime _eventDate = DateTime.now();
  File?    _coverFile;
  bool     _saving    = false;

  bool get _isEdit => widget.editAlbum != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _titleCtrl.text = widget.editAlbum!.title;
      _descCtrl.text  = widget.editAlbum!.description;
      _eventDate      = widget.editAlbum!.eventDate;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _eventDate,
      firstDate:   DateTime(2020),
      lastDate:    DateTime(2030),
      builder:     (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickCover() async {
    final xfile = await _picker.pickImage(
      source:    ImageSource.gallery,
      imageQuality: 80,
    );
    if (xfile != null) setState(() => _coverFile = File(xfile.path));
  }

  Future<void> _pickCoverCamera() async {
    final xfile = await _picker.pickImage(
      source:       ImageSource.camera,
      imageQuality: 80,
    );
    if (xfile != null) setState(() => _coverFile = File(xfile.path));
  }

  void _showPickOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title:   const Text('Choose from Gallery'),
              onTap:   () { Navigator.pop(context); _pickCover(); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title:   const Text('Take Photo'),
              onTap:   () { Navigator.pop(context); _pickCoverCamera(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _service.updateAlbum(
          widget.editAlbum!.id,
          title:       _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          eventDate:   _eventDate,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album updated')),
        );
        Navigator.pop(context);
      } else {
        final albumId = await _service.createAlbum(
          title:       _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          eventDate:   _eventDate,
          createdBy:   widget.userEmail,
        );
        // Upload cover photo if selected
        if (_coverFile != null) {
          await _service.uploadPhotos(
            albumId,
            [_coverFile!],
            widget.userEmail,
          );
        }
        final album = GalleryAlbum(
          id:            albumId,
          title:         _titleCtrl.text.trim(),
          description:   _descCtrl.text.trim(),
          eventDate:     _eventDate,
          coverPhotoUrl: '',
          createdBy:     widget.userEmail,
          createdAt:     DateTime.now(),
          photoCount:    _coverFile != null ? 1 : 0,
          isPublished:   false,
        );
        if (!mounted) return;
        Navigator.pop(context, album);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime dt) {
    const m = ['January','February','March','April','May','June',
                'July','August','September','October','November','December'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Album' : 'New Album'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cover photo picker
            GestureDetector(
              onTap: _showPickOptions,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color:        Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.hardEdge,
                child: _coverFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_coverFile!, fit: BoxFit.cover),
                          Positioned(
                            right: 8, bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color:  Colors.black54,
                                shape:  BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 48, color: Colors.grey.shade500),
                          const SizedBox(height: 8),
                          Text(
                            'Add Cover Photo (optional)',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Event Name
            TextFormField(
              controller: _titleCtrl,
              maxLength: 60,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: const InputDecoration(
                labelText:    'Event Name *',
                prefixIcon:   Icon(Icons.event_outlined),
                border:       OutlineInputBorder(),
                counterText:  '',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Event name is required' : null,
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descCtrl,
              maxLines:   3,
              maxLength: 200,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: const InputDecoration(
                labelText:    'Description',
                prefixIcon:   Icon(Icons.description_outlined),
                border:       OutlineInputBorder(),
                alignLabelWithHint: true,
                counterText:  '',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Event Date
            InkWell(
              onTap:        _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText:  'Event Date *',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  border:     OutlineInputBorder(),
                ),
                child: Text(
                  _fmtDate(_eventDate),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Save button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        _isEdit ? 'Save Changes' : 'Create Album',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
