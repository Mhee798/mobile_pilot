import 'package:flutter_edge_ai/flutter_edge_ai.dart';

// Group related actions to keep the model's tool catalog small.
const aiActionDefinitions = [
  Tool(
    name: 'keyboard_action',
    description: 'Send the focused editable field\'s keyboard action in the selected foreground app. After entering a search query and reading the UI, use key=search to submit. default presses the field\'s advertised action. No screenshot/capture_id is needed. Rejects unfocused/password/wrong-app fields.',
    parameters: {
      'type': 'object',
      'properties': {
        'key': {
          'type': 'string',
          'enum': ['default', 'search', 'next', 'enter'],
        },
      },
      'required': ['key'],
    },
  ),
  Tool(
    name: 'ui_action',
    description: 'Act on the REQUIRED ref copied from the latest UI element, not its list position. text is replacement content only, never a tap target. Old refs expire after a read/action; inspect the latest UI first.',
    parameters: {
      'type': 'object',
      'properties': {
        'ref': {
          'type': 'string',
          'description': 'REQUIRED target: copy the actual ref alias from the latest UI result.',
        },
        'action': {
          'type': 'string',
          'enum': ['tap', 'focus', 'replace', 'clear'],
        },
        'text': {
          'type': 'string',
          'description':
              'Replacement text, max 2000 chars. Only used for replace.',
        },
      },
      'required': ['ref', 'action'],
    },
  ),
  Tool(
    name: 'capture_screen',
    description: 'Capture the selected app. Returns capture_id and image when Vision is enabled. Coordinates use this image only; no UI tree/image synchronization is implied.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  Tool(
    name: 'screen_action',
    description: 'Act using a fresh capture_id. Coordinates are normalized 0..1 on that image. Read/capture again after each action. pinch scale <1 zooms out, >1 zooms in. scroll_down reveals content below. type_text replaces the focused editable field.',
    parameters: {
      'type': 'object',
      'properties': {
        'capture_id': {'type': 'string'},
        'action': {
          'type': 'string',
          'enum': [
            'tap',
            'double_tap',
            'long_press',
            'swipe',
            'drag',
            'pinch',
            'scroll_up',
            'scroll_down',
            'swipe_left',
            'swipe_right',
            'back',
            'type_text',
            'keyboard',
          ],
        },
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'end_x': {'type': 'number'},
        'end_y': {'type': 'number'},
        'duration_ms': {'type': 'integer'},
        'hold_ms': {'type': 'integer'},
        'scale': {'type': 'number'},
        'start_span': {'type': 'number'},
        'axis': {
          'type': 'string',
          'enum': ['horizontal', 'vertical'],
        },
        'text': {
          'type': 'string',
          'description': 'For type_text, 1..2000 chars; for keyboard: default/search/next/enter.',
        },
      },
      'required': ['capture_id', 'action'],
    },
  ),
  Tool(
    name: 'scroll_until_ui',
    description: 'Scroll the selected app until an exact selector is found. Bounded to 1..40 scrolls and 1..60 seconds. Does not tap. Read the UI after it finishes.',
    parameters: {
      'type': 'object',
      'properties': {
        'selector': {
          'type': 'string',
          'enum': ['text', 'contentDescription', 'resourceId'],
        },
        'value': {'type': 'string'},
        'direction': {
          'type': 'string',
          'enum': ['up', 'down'],
        },
        'max_scrolls': {'type': 'integer'},
        'timeout_seconds': {'type': 'integer'},
        'distance': {
          'type': 'string',
          'enum': ['app', 'short', 'long'],
        },
      },
      'required': [
        'selector',
        'value',
        'direction',
        'max_scrolls',
        'timeout_seconds',
      ],
    },
  ),
  Tool(
    name: 'navigate',
    description: 'System navigation. back applies only to the selected foreground app. home/recents do not confirm a target app switch; use open_app for a specific app.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['back', 'home', 'recents'],
        },
      },
      'required': ['action'],
    },
  ),
  Tool(
    name: 'device_status',
    description: 'Check Accessibility, floating controls, and selected target. Does not change settings.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  Tool(
    name: 'floating_controls',
    description:
        'Show/hide MobilePilot floating controls. Requires Accessibility.',
    parameters: {
      'type': 'object',
      'properties': {
        'enabled': {'type': 'boolean'},
      },
      'required': ['enabled'],
    },
  ),
  Tool(
    name: 'cancel_actions',
    description: 'Cancel pending native actions, capture and waits. Already dispatched actions may have happened.',
    parameters: {'type': 'object', 'properties': {}},
  ),
];
