using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using LumenInstaller.Core;

namespace LumenInstaller.Views;

/// A question of the installer: yes/no as buttons; a word such as ERASE has to be typed by the user. Closing the window
/// without an answer answers "no" (the installer then cancels, nothing written).
public partial class PromptWindow : Window
{
    readonly Prompt prompt;
    public string? Answer { get; private set; }
    public bool Withdrawn { get; private set; }

    /// The output went on: it was not a question after all. Closes without answering.
    public void Withdraw() { Withdrawn = true; Close(); }

    public PromptWindow(Prompt p)
    {
        InitializeComponent();
        prompt = p;
        var ctx = string.Join("\n", p.Context.Select(l => Regex.Replace(l, @"^\d\d:\d\d:\d\d\s+", "")));
        ContextText.Text = ctx;
        ContextBox.Visibility = ctx.Trim().Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        Question.Text = Regex.Replace(p.Question, @"\s*\[(да/нет|yes/no)\]\s*:?\s*$", "");
        switch (p.Kind)
        {
            case PromptKind.YesNo:
                YesNo.Visibility = Visibility.Visible;
                break;
            case PromptKind.Word:
                Word.Visibility = Visibility.Visible;
                WordLabel.Text = Loc.F("prompt.type", p.Word!);
                Header.Text = Loc.T("prompt.danger");
                Glyph.Text = "⚠";
                Glyph.Foreground = (System.Windows.Media.Brush)FindResource("Bad");
                Loaded += (_, _) => WordBox.Focus();
                break;
            case PromptKind.Enter:
                Free.Visibility = Visibility.Visible;
                FreeBox.Visibility = Visibility.Collapsed;
                FreeButton.Content = Loc.T("inst.done");
                break;
            default:
                Free.Visibility = Visibility.Visible;
                Loaded += (_, _) => FreeBox.Focus();
                break;
        }
    }

    // ASCII answers: the script accepts yes/no in both of its languages, whatever the console input code page
    void Yes_Click(object s, RoutedEventArgs e) { Answer = "yes"; Close(); }
    void No_Click(object s, RoutedEventArgs e) { Answer = "no"; Close(); }
    void Word_Click(object s, RoutedEventArgs e) { if (WordBox.Text == prompt.Word) { Answer = WordBox.Text; Close(); } }
    void Free_Click(object s, RoutedEventArgs e) { Answer = FreeBox.Text; Close(); }
    void WordBox_TextChanged(object s, TextChangedEventArgs e) => Continue.IsEnabled = WordBox.Text == prompt.Word;
    void WordBox_KeyDown(object s, KeyEventArgs e) { if (e.Key == Key.Enter) Word_Click(s, e); }
}
