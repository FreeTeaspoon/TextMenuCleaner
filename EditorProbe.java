import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Runs without attaching an editor UI or sending selected text. */
public final class EditorProbe {
    private static final String[] PATCHED = {
        "miuix.textaction.Query",
        "miuix.textaction.Translate",
        "miuix.textaction.Phrases",
    };

    public static void main(String[] args) throws Exception {
        ClassLoader loader = (ClassLoader) Class.forName("dalvik.system.PathClassLoader").getConstructor(String.class, ClassLoader.class).newInstance(args[0], EditorProbe.class.getClassLoader());
        boolean patched = args[1].equals("patched");
        String[] names = args.length > 2 ? java.util.Arrays.copyOfRange(args, 2, args.length) : PATCHED;
        for (String name : names) {
            Class<?> type = loader.loadClass(name);
            Object action = type.getDeclaredConstructor().newInstance();
            Method method = type.getDeclaredMethod("onInvalidated");
            method.setAccessible(true);
            boolean threw = false;
            try { method.invoke(action); }
            catch (InvocationTargetException e) {
                if (!(e.getCause() instanceof NullPointerException)) throw e;
                threw = true;
            }
            // The unpatched producers require an attached editor. Patched methods are no-ops.
            if (threw == patched) throw new AssertionError(name + " unexpected behavior");
            System.out.println("PASS " + name + " " + args[1]);
        }
        for (String name : new String[]{"Classify", "Select", "AskHyperXiaoai", "AiRecognition"})
            loader.loadClass("miuix.textaction." + name);
        System.out.println("PASS remaining action classes load");
    }
}
