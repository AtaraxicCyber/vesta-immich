import 'package:flutter/material.dart';

enum ImmichColorPreset { indigo, deepPurple, pink, red, orange, yellow, lime, green, cyan, slateGray }

// Vesta brand: flame orange from the logo (darker on light backgrounds for contrast).
// The default preset (`indigo`) reads these, so it renders as Vesta orange.
const Color immichBrandColorLight = Color(0xFFD65400);
const Color immichBrandColorDark = Color(0xFFF07328);
const Color whiteOpacity75 = Color.fromRGBO(255, 255, 255, 0.75);
