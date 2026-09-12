// 最小占位实现，仅供 mono 解析 ImageMagick 方法表签名使用。
// 编译器在 Linux 下不会真正走 WPF 渲染路径，因此无需真实实现。
namespace System.Windows.Media
{
    public class ImageSource { }
}
namespace System.Windows.Media.Imaging
{
    public class BitmapSource : System.Windows.Media.ImageSource { }
    public class BitmapEncoder { }
    public class BitmapFrame : BitmapSource { }
}