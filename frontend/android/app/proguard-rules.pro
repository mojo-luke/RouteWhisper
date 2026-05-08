# AutoValue is a compile-time annotation processor; its annotation classes
# don't need to exist at runtime. Mapbox model classes (e.g. directions.v5.models.Admin)
# reference them, so silence the R8 warning.
-dontwarn com.google.auto.value.AutoValue
-dontwarn com.google.auto.value.AutoValue$Builder
