# Fuer WPF-Items, deren Properties **nach** dem Hinzufuegen zur ItemsSource noch gesetzt werden (lazy thumbnails, async loads), reicht POCO nicht — die Klasse muss `INotifyPropertyChanged` implementieren.

**Warum:** Eine via `Add-Type` erstellte C#-POCO ohne `INotifyPropertyChanged` wird gebunden, aber spaetere Property-Set-Operationen aktualisieren die UI **nicht**. WPF subscribed beim Binding auf `PropertyChanged`; ohne dieses Event bleibt das gerenderte Bild leer/alt. Bei AP 8: Thumbnail-Property wurde nach `Items.Add` nachgeladen — ohne INPC waeren die Tiles dauerhaft leer geblieben.

**Wie anwenden:** Add-Type-Klasse mit `INotifyPropertyChanged` definieren, im Setter `OnPropertyChanged(name)` aufrufen. Properties die direkt beim Konstruktor gesetzt werden brauchen kein INPC.

```csharp
public class HistoryEntry : INotifyPropertyChanged {
    public string FileName { get; set; }            // einmalig -> POCO reicht
    private BitmapSource _thumbnail;
    public BitmapSource Thumbnail {                  // lazy -> INPC noetig
        get { return _thumbnail; }
        set { _thumbnail = value; OnPropertyChanged("Thumbnail"); }
    }
    public event PropertyChangedEventHandler PropertyChanged;
    protected void OnPropertyChanged(string n) {
        var h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(n));
    }
}
```

Verwandt: [[psCustomObject-binding-leer]] (PSCustomObject reicht generell nicht fuer WPF-Bindings).
